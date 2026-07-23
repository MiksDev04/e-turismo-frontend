import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/local_database.dart';
import 'session_service.dart';
import 'connectivity_service.dart';
import '../../api/login_api.dart';

export 'connectivity_service.dart';

// =============================================================================
// OFFLINE AUTH SERVICE
// =============================================================================

class OfflineAuthService {
  OfflineAuthService._internal();
  static final OfflineAuthService instance = OfflineAuthService._internal();

  Future<void> cacheProfile({
    required String id,
    required String username,
    required String password,
    String? fullName,
    String? email,
    String? phone,
    String? role,
    String? createdAt,
    String? updatedAt,
    Map<String, dynamic>? business,
  }) async {
    final db = await LocalDatabase.instance.database;
    final hash = _hashPassword(password, id);

    await db.transaction((txn) async {
      final profileData = {
        'id': id,
        'username': username,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'role': role,
        'password_hash': hash,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
      
      final pCount = await txn.update(
        LocalDatabase.tableLocalProfiles,
        profileData,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (pCount == 0) {
        await txn.insert(LocalDatabase.tableLocalProfiles, profileData);
      }

      if (business != null) {
        final bizData = {
          'id': business['id'],
          'profile_id': id,
          'business_name': business['business_name'],
          'status': business['status'],
          'permit_number': business['permit_number'],
          'registration_number': business['registration_number'],
          'street': business['street'],
          'region': business['region'],
          'city_municipality': business['city_municipality'],
          'province': business['province'],
          'barangay': business['barangay'],
          'tradename': business['tradename'],
          'business_line': business['business_line'] is String
              ? business['business_line']
              : jsonEncode(business['business_line']),
          'owner_first_name': business['owner_first_name'],
          'owner_last_name': business['owner_last_name'],
          'owner_middle_name': business['owner_middle_name'],
          'business_type': business['business_type'],
          'created_at': business['created_at'],
          'updated_at': business['updated_at'],
        };

        final bCount = await txn.update(
          LocalDatabase.tableLocalBusinesses,
          bizData,
          where: 'id = ?',
          whereArgs: [business['id']],
        );
        if (bCount == 0) {
          await txn.insert(LocalDatabase.tableLocalBusinesses, bizData);
        }
      }
    });
  }

  Future<Map<String, dynamic>?> verifyOfflineLogin({
    required String username,
    required String password,
  }) async {
    final db = await LocalDatabase.instance.database;

    final rows = await db.query(
      LocalDatabase.tableLocalProfiles,
      where: 'username = ? OR email = ?',
      whereArgs: [username, username],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final profile = rows.first;
    final expectedHash = _hashPassword(password, profile['id'] as String);

    if (profile['password_hash'] != expectedHash) return null;

    return profile;
  }

  String _hashPassword(String password, String userId) {
    final bytes = utf8.encode(password + userId);
    return sha256.convert(bytes).toString();
  }
}

// =============================================================================
// SYNC STATE
// =============================================================================

enum SyncStatus { idle, syncing, synced, error }

class SyncState {
  final SyncStatus status;
  final int pendingCount;
  final String? errorMessage;

  const SyncState({
    required this.status,
    this.pendingCount = 0,
    this.errorMessage,
  });
}

// =============================================================================
// PUSH RESULT
// Lightweight outcome report from a push batch so sync() can tell the
// difference between "everything synced", "some records were rejected", and
// "the connection dropped mid-batch" — instead of always reporting success.
// =============================================================================

class _PushResult {
  final int failed;
  final bool networkLost;
  const _PushResult({this.failed = 0, this.networkLost = false});
}

// =============================================================================
// SYNC SERVICE
// =============================================================================

class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  String get _baseUrl {
    if (kIsWeb) {
      return const String.fromEnvironment(
        'BACKEND_URL',
        defaultValue: 'http://localhost:3000',
      );
    } else if (Platform.isAndroid) {
      return dotenv.env['ANDROID_BACKEND_URL'] ?? 'http://10.0.2.2:3000';
    } else {
      return dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
    }
  }

  Map<String, String> get _headers {
    final Map<String, String> h = {
      'Content-Type': 'application/json',
      'x-api-key': kIsWeb
          ? const String.fromEnvironment('API_KEY', defaultValue: '')
          : (dotenv.env['API_KEY'] ?? 'tourism_app_v2_secret_key_2026'),
    };

    final token = SessionService.instance.current?.token;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }

    return h;
  }

  final StreamController<SyncState> _controller =
      StreamController<SyncState>.broadcast();
  Stream<SyncState> get syncStateStream => _controller.stream;

  SyncState _state = const SyncState(status: SyncStatus.idle);
  SyncState get currentState => _state;

  static const _syncDelay = Duration(milliseconds: 500);
  static const _minRetryInterval = Duration(seconds: 30);
  static const _fullSyncInterval = Duration(hours: 24);
  static const _prefKeyLastSync = 'sync_lastSyncTimestamp';
  static const _prefKeyLastFullSync = 'sync_lastFullSyncTimestamp';
  DateTime? _lastSyncEnd;

  void listenForConnectivity() {
    // 1. Listen for future changes
    ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        _handleOnlineTransition();
      }
    });

    // 2. Initial check: if already online, trigger sync immediately
    if (ConnectivityService.instance.isOnline) {
      _handleOnlineTransition();
    }
  }

  Future<void> _handleOnlineTransition() async {
    final session = SessionService.instance.current;

    // Session not loaded yet — retry after a short delay.
    if (session == null) {
      debugPrint('⏳ _handleOnlineTransition: session not ready — retrying in 2s');
      Future.delayed(const Duration(seconds: 2), _handleOnlineTransition);
      return;
    }

    // Session loaded but not a business account — stop, no sync needed.
    if (session.role != 'business') {
      debugPrint('⏭ _handleOnlineTransition: skipped — role is ${session.role}');
      return;
    }

    // ── Auto-Cloud-Upgrade ──────────────────────────────────────────────────
    // If we are online but have no token, attempt to get one using stored password.
    if (session.password != null &&
        (session.token == null || session.isOfflineSession)) {
      debugPrint(
        '☁️ SyncService: Online detected. Refreshing token before sync...',
      );
      try {
        await LoginApi().backgroundAuth(
          username: session.username ?? session.email,
          password: session.password!,
        );
      } catch (e) {
        debugPrint('⚠️ SyncService: Auto-auth error: $e');
      }
    }

    try {
      // Fetch profile and business to ensure SQLite has the business record.
      await _pullProfileAndBusiness();

      final current = SessionService.instance.current;
      String? businessId = current?.businessId;

      if (businessId == null && current != null) {
        final db = await LocalDatabase.instance.database;
        final rows = await db.query(
          LocalDatabase.tableLocalBusinesses,
          where: 'profile_id = ?',
          whereArgs: [current.userId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          businessId = rows.first['id'] as String?;
        }
      }

      if (businessId != null) {
        await _pullRoomsFromBackend(businessId: businessId, forceFullSync: true);
        await _pullFromBackend(businessId: businessId, forceFullSync: true);
      }
    } catch (e) {
      debugPrint('⚠️ _handleOnlineTransition: initial pulls failed: $e');
    }

    await _clearOfflineSessionFlag();

    // Give a small delay for state to settle before full sync.
    Future.delayed(_syncDelay, sync);
  }

  Future<void> _clearOfflineSessionFlag() async {
    final current = SessionService.instance.current;
    if (current == null || !current.isOfflineSession) return;

    final updated = current.copyWith(isOfflineSession: false);

    await SessionService.instance.save(updated);
    await SessionService.instance.loadAndCache();
    debugPrint('✅ _clearOfflineSessionFlag: isOfflineSession reset to false');
  }

  Future<void> sync() async {
    if (kIsWeb) {
      debugPrint('⏭ sync: skipped on web — local SQLite is disabled');
      return;
    }

    final session = SessionService.instance.current;
    if (session == null || session.role != 'business') {
      debugPrint('⏭ sync: skipped — only for business accounts');
      return;
    }

    if (_state.status == SyncStatus.syncing) return;

    if (!ConnectivityService.instance.isOnline) {
      debugPrint('⏭ sync: skipped — device is offline');
      return;
    }

    if (_lastSyncEnd != null &&
        DateTime.now().difference(_lastSyncEnd!) < _minRetryInterval &&
        _state.status == SyncStatus.error) {
      debugPrint('⏳ sync: cooldown — skipping, last sync ended less than 30s ago');
      return;
    }

    // Claim the "syncing" lock synchronously, BEFORE the first `await` below.
    // This closes a race window: two near-simultaneous callers (connectivity
    // listener, the 5s polling timer, a manual "Sync Now" tap, or the
    // post-save trigger in the guest entry page) could previously both pass
    // the guard above while the first call was still awaiting _countPending(),
    // letting both push the same pending record at the same time — which is
    // what caused the "Lock wait timeout exceeded" MySQL errors.
    _emit(SyncState(status: SyncStatus.syncing, pendingCount: _state.pendingCount));

    final initialPending = await _countPending();
    debugPrint('🔄 sync: starting sync process. Initial pending count: $initialPending');
    _emit(SyncState(status: SyncStatus.syncing, pendingCount: initialPending));

    try {
      await _pullProfileAndBusiness();

      // Phase 1: Pull rooms from backend (ensures local room cache is fresh)
      await _pullRoomsFromBackend();

      // Phase 2: Push pending room changes (creates then updates)
      final roomCreateResult = await _pushPendingRoomCreates();
      if (roomCreateResult.networkLost) {
        final remaining = await _countPending();
        _emit(SyncState(
          status: SyncStatus.error,
          errorMessage: 'Connection lost during room sync — will retry automatically',
          pendingCount: remaining,
        ));
        return;
      }

      final roomUpdateResult = await _pushPendingRoomUpdates();
      if (roomUpdateResult.networkLost) {
        final remaining = await _countPending();
        _emit(SyncState(
          status: SyncStatus.error,
          errorMessage: 'Connection lost during room sync — will retry automatically',
          pendingCount: remaining,
        ));
        return;
      }

      // Phase 3: Push pending guest record changes
      final createResult = await _pushPendingCreates(); // POST → /api/business/guest-entries
      if (createResult.networkLost) {
        final remaining = await _countPending();
        _emit(SyncState(
          status: SyncStatus.error,
          errorMessage: 'Connection lost during sync — will retry automatically',
          pendingCount: remaining,
        ));
        return;
      }

      final updateResult = await _pushPendingUpdates(); // PUT  → /api/business/guest-records/:id
      if (updateResult.networkLost) {
        final remaining = await _countPending();
        _emit(SyncState(
          status: SyncStatus.error,
          errorMessage: 'Connection lost during sync — will retry automatically',
          pendingCount: remaining,
        ));
        return;
      }

      await _pullFromBackend();                         // GET  → /api/business/guest-records

      final remaining = await _countPending();
      final anyFailed = roomCreateResult.failed > 0 ||
          roomUpdateResult.failed > 0 ||
          createResult.failed > 0 ||
          updateResult.failed > 0;

      if (anyFailed) {
        _emit(SyncState(
          status: SyncStatus.error,
          errorMessage: '$remaining record(s) failed to sync',
          pendingCount: remaining,
        ));
      } else {
        _emit(SyncState(status: SyncStatus.synced, pendingCount: remaining));
      }
    } catch (e) {
      _emit(
        SyncState(
          status: SyncStatus.error,
          errorMessage: e.toString(),
          pendingCount: await _countPending(),
        ),
      );
    } finally {
      _lastSyncEnd = DateTime.now();
    }
  }

  Future<int> getPendingCount() => _countPending();

  // ---------------------------------------------------------------------------
  // PUSH PENDING CREATES
  // Uses POST /api/business/guest-entries so the backend treats them as new
  // records. The saved UUID is forwarded as `id` so the cloud uses the same
  // primary key that SQLite already has — avoiding duplicates on re-sync.
  // ---------------------------------------------------------------------------
  Future<_PushResult> _pushPendingCreates() async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pushPendingCreates: skipped — Backend unreachable');
      return const _PushResult();
    }

    final db = await LocalDatabase.instance.database;

    final records = await db.query(
      LocalDatabase.tableGuestRecords,
      where: 'sync_status = ?',
      whereArgs: [LocalDatabase.syncPendingCreate],
    );

    if (records.isNotEmpty) {
      debugPrint('📤 _pushPendingCreates: ${records.length} record(s) to push');
    }

    int failed = 0;

    for (final record in records) {
      final recordId = record['id'] as String;

      if (!await _canReachBackend()) {
        debugPrint(
          '🌐 _pushPendingCreates: connectivity lost — aborting batch',
        );
        return _PushResult(failed: failed, networkLost: true);
      }

      try {
        // Read room IDs from junction table
        final roomLinks = await db.query(
          LocalDatabase.tableGuestRecordRooms,
          columns: ['room_id'],
          where: 'guest_record_id = ?',
          whereArgs: [recordId],
        );
        final roomIds = roomLinks.map((r) => r['room_id'] as String).toList();

        // Build payload and include the local UUID so the backend stores the
        // same ID — keeps SQLite and MySQL in sync without a remapping step.
        final payload = _toApiPayload(record, roomIds, isCreate: true);
        payload['id'] = recordId;

        final response = await http
            .post(
              Uri.parse('$_baseUrl/api/business/guest-entries'),
              headers: _headers,
              body: jsonEncode(payload),
            )
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw TimeoutException(
                'POST guest-entries/$recordId timed out',
              ),
            );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await db.update(
            LocalDatabase.tableGuestRecords,
            {
              'sync_status': LocalDatabase.syncSynced,
              'local_updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [recordId],
          );
          debugPrint('✅ _pushPendingCreates: synced $recordId');
        } else if (response.statusCode == 401) {
          debugPrint(
            '🔐 _pushPendingCreates: 401 — token expired, refreshing and aborting for retry',
          );
          await _tryRefreshToken();
          return _PushResult(failed: failed); // Stop batch — next sync will use the fresh token.
        } else if (response.statusCode == 409) {
          // The server already has a guest_records row with this id. Since
          // the id is a UUID we generated on-device, this almost never means
          // a genuine clash with someone else's data — it means our own
          // earlier POST actually succeeded, but its 2xx response was lost
          // (e.g. connectivity dropped right as the server committed, which
          // is exactly what happens when the network is cut mid-sync). The
          // record is already safely stored; treat this as synced instead of
          // failing so it doesn't retry-and-409 forever.
          await db.update(
            LocalDatabase.tableGuestRecords,
            {
              'sync_status': LocalDatabase.syncSynced,
              'local_updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [recordId],
          );
          debugPrint(
            '♻️ _pushPendingCreates: $recordId already existed on server — marking synced',
          );
        } else {
          failed++;
          debugPrint(
            '❌ _pushPendingCreates: failed for $recordId — '
            '${response.statusCode} ${response.body}',
          );
        }
      } catch (e) {
        if (isNetworkError(e)) {
          debugPrint(
            '🌐 _pushPendingCreates: connection lost mid-push for $recordId — aborting batch ($e)',
          );
          return _PushResult(failed: failed, networkLost: true);
        }
        failed++;
        debugPrint('❌ _pushPendingCreates: exception for $recordId — $e');
      }
    }

    return _PushResult(failed: failed);
  }

  // ---------------------------------------------------------------------------
  // PUSH PENDING UPDATES
  // Uses PUT /api/business/guest-records/:id (upsert semantics on the backend).
  // ---------------------------------------------------------------------------
  Future<_PushResult> _pushPendingUpdates() async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pushPendingUpdates: skipped — Backend unreachable');
      return const _PushResult();
    }

    final db = await LocalDatabase.instance.database;

    final records = await db.query(
      LocalDatabase.tableGuestRecords,
      where: 'sync_status = ?',
      whereArgs: [LocalDatabase.syncPendingUpdate],
    );

    if (records.isNotEmpty) {
      debugPrint('📤 _pushPendingUpdates: ${records.length} record(s) to push');
    }

    int failed = 0;

    for (final record in records) {
      final recordId = record['id'] as String;

      if (!await _canReachBackend()) {
        debugPrint(
          '🌐 _pushPendingUpdates: connectivity lost — aborting batch',
        );
        return _PushResult(failed: failed, networkLost: true);
      }

      try {
        // Read room IDs from junction table
        final roomLinks = await db.query(
          LocalDatabase.tableGuestRecordRooms,
          columns: ['room_id'],
          where: 'guest_record_id = ?',
          whereArgs: [recordId],
        );
        final roomIds = roomLinks.map((r) => r['room_id'] as String).toList();

        final payload = _toApiPayload(record, roomIds, isCreate: false);

        final response = await http
            .put(
              Uri.parse('$_baseUrl/api/business/guest-records/$recordId'),
              headers: _headers,
              body: jsonEncode(payload),
            )
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw TimeoutException(
                'PUT guest-records/$recordId timed out',
              ),
            );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await db.update(
            LocalDatabase.tableGuestRecords,
            {
              'sync_status': LocalDatabase.syncSynced,
              'local_updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [recordId],
          );
          debugPrint('✅ _pushPendingUpdates: synced $recordId');
        } else if (response.statusCode == 401) {
          debugPrint(
            '🔐 _pushPendingUpdates: 401 — token expired, refreshing and aborting for retry',
          );
          await _tryRefreshToken();
          return _PushResult(failed: failed);
        } else {
          failed++;
          debugPrint(
            '❌ _pushPendingUpdates: failed for $recordId — '
            '${response.statusCode} ${response.body}',
          );
        }
      } catch (e) {
        if (isNetworkError(e)) {
          debugPrint(
            '🌐 _pushPendingUpdates: connection lost mid-push for $recordId — aborting batch ($e)',
          );
          return _PushResult(failed: failed, networkLost: true);
        }
        failed++;
        debugPrint('❌ _pushPendingUpdates: exception for $recordId — $e');
      }
    }

    return _PushResult(failed: failed);
  }

  // ---------------------------------------------------------------------------
  // Safe room upsert — avoids INSERT OR REPLACE which triggers DELETE and
  // violates ON DELETE RESTRICT foreign keys from local_guest_record_rooms.
  // Uses SQLite's native UPSERT syntax instead.
  // ---------------------------------------------------------------------------
  Future<void> _safeUpsertRoom(
    Database db, {
    required String id,
    required String businessId,
    required String roomNumber,
    required int capacity,
    required String roomStatus,
    required String syncStatus,
    String? createdAt,
    String? updatedAt,
    String? localUpdatedAt,
  }) async {
    await db.rawInsert(
      'INSERT INTO ${LocalDatabase.tableLocalRooms} '
      '(id, business_id, room_number, capacity, room_status, created_at, updated_at, sync_status, local_updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET '
      'business_id=excluded.business_id, room_number=excluded.room_number, '
      'capacity=excluded.capacity, room_status=excluded.room_status, '
      'created_at=COALESCE(excluded.created_at, ${LocalDatabase.tableLocalRooms}.created_at), '
      'updated_at=COALESCE(excluded.updated_at, ${LocalDatabase.tableLocalRooms}.updated_at), '
      'sync_status=excluded.sync_status, local_updated_at=excluded.local_updated_at',
      [id, businessId, roomNumber, capacity, roomStatus, createdAt, updatedAt, syncStatus, localUpdatedAt],
    );
  }

  // ---------------------------------------------------------------------------
  // PULL ROOMS FROM BACKEND (Delta Sync)
  // Fetches rooms for the business and upserts them into local_rooms.
  // Uses delta sync: only rooms modified since lastSync are returned.
  // ---------------------------------------------------------------------------
  Future<void> _pullRoomsFromBackend({String? businessId, bool forceFullSync = false}) async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pullRoomsFromBackend: skipped — Backend unreachable');
      return;
    }

    final db = await LocalDatabase.instance.database;

    final businesses = businessId != null
        ? [{'id': businessId}]
        : await db.query(
            LocalDatabase.tableLocalBusinesses,
            columns: ['id'],
          );

    // Determine if this should be a full sync or delta sync
    final needsFull = forceFullSync || await _needsFullSync();
    final lastSync = needsFull ? null : await _getLastSyncTimestamp();

    for (final business in businesses) {
      final bizId = business['id'] as String;

      try {
        final url = lastSync != null
            ? '$_baseUrl/api/business/rooms?businessId=$bizId&lastSync=$lastSync'
            : '$_baseUrl/api/business/rooms?businessId=$bizId&fetchAll=true';

        final response = await http.get(Uri.parse(url), headers: _headers);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint('⚠️ _pullRoomsFromBackend: HTTP ${response.statusCode} for $bizId');
          continue;
        }

        final decoded = jsonDecode(response.body);
        final data = decoded is Map ? (decoded['data'] as List? ?? []) : [];
        final remoteIds = <String>{};

        for (final r in data) {
          final roomId = r['id'] as String;
          remoteIds.add(roomId);

          // Skip rooms that have local pending changes (user edited them offline)
          final existing = await db.query(
            LocalDatabase.tableLocalRooms,
            columns: ['sync_status'],
            where: 'id = ?',
            whereArgs: [roomId],
            limit: 1,
          );
          if (existing.isNotEmpty) {
            final localSync = existing.first['sync_status'] as String?;
            if (localSync != null && localSync != LocalDatabase.syncSynced) {
              debugPrint('⏳ _pullRoomsFromBackend: skipping room $roomId (local pending: $localSync)');
              continue;
            }
          }

          await _safeUpsertRoom(
            db,
            id:               roomId,
            businessId:       bizId,
            roomNumber:       r['roomNumber'] ?? r['room_number'] ?? roomId.substring(0, 8),
            capacity:         r['capacity'] ?? 1,
            roomStatus:       r['roomStatus'] ?? r['room_status'] ?? 'vacant',
            createdAt:        r['createdAt'] ?? r['created_at'],
            updatedAt:        r['updatedAt'] ?? r['updated_at'],
            syncStatus:       LocalDatabase.syncSynced,
            localUpdatedAt:   null,
          );
        }

        // Only prune local rooms during full sync (delta only returns
        // changed rooms, so absence doesn't mean deletion).
        if (lastSync == null) {
          final localSynced = await db.query(
            LocalDatabase.tableLocalRooms,
            columns: ['id'],
            where: 'business_id = ? AND sync_status = ?',
            whereArgs: [bizId, LocalDatabase.syncSynced],
          );

          for (final local in localSynced) {
            final id = local['id'] as String;
            if (!remoteIds.contains(id)) {
              final refs = await db.query(
                LocalDatabase.tableGuestRecordRooms,
                columns: ['id'],
                where: 'room_id = ?',
                whereArgs: [id],
                limit: 1,
              );
              if (refs.isNotEmpty) continue;

              debugPrint('🧹 _pullRoomsFromBackend: pruning local room $id (not on cloud)');
              await db.delete(
                LocalDatabase.tableLocalRooms,
                where: 'id = ?',
                whereArgs: [id],
              );
            }
          }
        }

        debugPrint('✅ _pullRoomsFromBackend: synced ${data.length} rooms for $bizId');
      } on SocketException catch (e) {
        debugPrint('🌐 _pullRoomsFromBackend: network lost — aborting ($e)');
        return;
      } catch (e) {
        debugPrint('❌ _pullRoomsFromBackend: failed for $bizId — $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PUSH PENDING ROOM CREATES
  // POST /api/business/rooms — rooms created offline.
  // ---------------------------------------------------------------------------
  Future<_PushResult> _pushPendingRoomCreates() async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pushPendingRoomCreates: skipped — Backend unreachable');
      return const _PushResult();
    }

    final db = await LocalDatabase.instance.database;

    final records = await db.query(
      LocalDatabase.tableLocalRooms,
      where: 'sync_status = ?',
      whereArgs: [LocalDatabase.syncPendingCreate],
    );

    if (records.isNotEmpty) {
      debugPrint('📤 _pushPendingRoomCreates: ${records.length} room(s) to push');
    }

    int failed = 0;

    for (final record in records) {
      final roomId = record['id'] as String;

      if (!await _canReachBackend()) {
        debugPrint('🌐 _pushPendingRoomCreates: connectivity lost — aborting batch');
        return _PushResult(failed: failed, networkLost: true);
      }

      try {
        final payload = {
          'id':         roomId,
          'businessId': record['business_id'],
          'roomNumber': record['room_number'],
          'capacity':   record['capacity'],
        };

        final response = await http
            .post(
              Uri.parse('$_baseUrl/api/business/rooms'),
              headers: _headers,
              body: jsonEncode(payload),
            )
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw TimeoutException(
                'POST rooms/$roomId timed out',
              ),
            );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          await db.update(
            LocalDatabase.tableLocalRooms,
            {
              'sync_status':      LocalDatabase.syncSynced,
              'local_updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [roomId],
          );
          debugPrint('✅ _pushPendingRoomCreates: synced $roomId');
        } else if (response.statusCode == 401) {
          debugPrint('🔐 _pushPendingRoomCreates: 401 — token expired');
          await _tryRefreshToken();
          return _PushResult(failed: failed);
        } else if (response.statusCode == 409) {
          await db.update(
            LocalDatabase.tableLocalRooms,
            {
              'sync_status':      LocalDatabase.syncSynced,
              'local_updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [roomId],
          );
          debugPrint('♻️ _pushPendingRoomCreates: $roomId already existed — marking synced');
        } else {
          failed++;
          debugPrint(
            '❌ _pushPendingRoomCreates: failed for $roomId — '
            '${response.statusCode} ${response.body}',
          );
        }
      } catch (e) {
        if (isNetworkError(e)) {
          debugPrint('🌐 _pushPendingRoomCreates: connection lost for $roomId — aborting ($e)');
          return _PushResult(failed: failed, networkLost: true);
        }
        failed++;
        debugPrint('❌ _pushPendingRoomCreates: exception for $roomId — $e');
      }
    }

    return _PushResult(failed: failed);
  }

  // ---------------------------------------------------------------------------
  // PUSH PENDING ROOM UPDATES
  // PUT /api/business/rooms/:id — rooms edited offline.
  // ---------------------------------------------------------------------------
  Future<_PushResult> _pushPendingRoomUpdates() async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pushPendingRoomUpdates: skipped — Backend unreachable');
      return const _PushResult();
    }

    final db = await LocalDatabase.instance.database;

    final records = await db.query(
      LocalDatabase.tableLocalRooms,
      where: 'sync_status = ?',
      whereArgs: [LocalDatabase.syncPendingUpdate],
    );

    if (records.isNotEmpty) {
      debugPrint('📤 _pushPendingRoomUpdates: ${records.length} room(s) to push');
    }

    int failed = 0;

    for (final record in records) {
      final roomId = record['id'] as String;

      if (!await _canReachBackend()) {
        debugPrint('🌐 _pushPendingRoomUpdates: connectivity lost — aborting batch');
        return _PushResult(failed: failed, networkLost: true);
      }

      try {
        final payload = {
          'roomNumber': record['room_number'],
          'capacity':   record['capacity'],
        };

        final response = await http
            .put(
              Uri.parse('$_baseUrl/api/business/rooms/$roomId'),
              headers: _headers,
              body: jsonEncode(payload),
            )
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () => throw TimeoutException(
                'PUT rooms/$roomId timed out',
              ),
            );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          // Also sync room_status via the dedicated status endpoint
          try {
            final statusPayload = {'roomStatus': record['room_status']};
            final statusResponse = await http
                .put(
                  Uri.parse('$_baseUrl/api/business/rooms/$roomId/status'),
                  headers: _headers,
                  body: jsonEncode(statusPayload),
                )
                .timeout(
                  const Duration(seconds: 15),
                  onTimeout: () => throw TimeoutException(
                    'PUT rooms/$roomId/status timed out',
                  ),
                );
            if (statusResponse.statusCode >= 200 && statusResponse.statusCode < 300) {
              debugPrint('✅ _pushPendingRoomUpdates: synced room status for $roomId');
            } else {
              debugPrint('⚠️ _pushPendingRoomUpdates: room status sync failed for $roomId — ${statusResponse.statusCode}');
            }
          } catch (e) {
            debugPrint('⚠️ _pushPendingRoomUpdates: room status sync exception for $roomId — $e');
          }

          await db.update(
            LocalDatabase.tableLocalRooms,
            {
              'sync_status':      LocalDatabase.syncSynced,
              'local_updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [roomId],
          );
          debugPrint('✅ _pushPendingRoomUpdates: synced $roomId');
        } else if (response.statusCode == 401) {
          debugPrint('🔐 _pushPendingRoomUpdates: 401 — token expired');
          await _tryRefreshToken();
          return _PushResult(failed: failed);
        } else {
          failed++;
          debugPrint(
            '❌ _pushPendingRoomUpdates: failed for $roomId — '
            '${response.statusCode} ${response.body}',
          );
        }
      } catch (e) {
        if (isNetworkError(e)) {
          debugPrint('🌐 _pushPendingRoomUpdates: connection lost for $roomId — aborting ($e)');
          return _PushResult(failed: failed, networkLost: true);
        }
        failed++;
        debugPrint('❌ _pushPendingRoomUpdates: exception for $roomId — $e');
      }
    }

    return _PushResult(failed: failed);
  }

  // ---------------------------------------------------------------------------
  // PULL FROM BACKEND (Delta Sync)
  // ---------------------------------------------------------------------------
  Future<void> _pullFromBackend({String? businessId, bool forceFullSync = false}) async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pullFromBackend: skipped — Backend unreachable');
      return;
    }

    final db = await LocalDatabase.instance.database;

    final businesses = businessId != null
        ? [{'id': businessId}]
        : await db.query(
            LocalDatabase.tableLocalBusinesses,
            columns: ['id'],
          );

    // Determine if this should be a full sync or delta sync
    final needsFull = forceFullSync || await _needsFullSync();
    final lastSync = needsFull ? null : await _getLastSyncTimestamp();

    if (needsFull) {
      debugPrint('📥 _pullFromBackend: FULL sync (no lastSync)');
    } else {
      debugPrint('📥 _pullFromBackend: DELTA sync (lastSync=$lastSync)');
    }

    // Capture the sync timestamp BEFORE the requests so we don't miss records
    // modified between the request and the response.
    final syncTimestamp = DateTime.now().toUtc().toIso8601String();

    for (final business in businesses) {
      final businessId = business['id'] as String;

      try {
        // ── Build URL ───────────────────────────────────────────────────
        // When lastSync is present, the backend returns ALL statuses
        // (active + archived) AND is_deleted records so we can detect changes.
        // When doing a full sync, fetch active and archived separately as before.
        final allRemoteRecords = <Map<String, dynamic>>[];
        final seenIds = <String>{};

        if (lastSync != null) {
          // Delta sync: single request, server returns only changed records
          final url =
              '$_baseUrl/api/business/guest-records'
              '?businessId=$businessId'
              '&fetchAll=true'
              '&lastSync=$lastSync';
          final response = await http.get(Uri.parse(url), headers: _headers);
          if (response.statusCode >= 200 && response.statusCode < 300) {
            final decoded = jsonDecode(response.body);
            final records = decoded is List<dynamic>
                ? decoded
                : (decoded is Map ? (decoded['data'] as List? ?? []) : []);
            for (final r in records) {
              final id = r['id'] as String;
              if (seenIds.add(id)) {
                allRemoteRecords.add(Map<String, dynamic>.from(r));
              }
            }
          }
        } else {
          // Full sync: fetch both active and archived (existing behavior)
          final baseUrl =
              '$_baseUrl/api/business/guest-records'
              '?businessId=$businessId'
              '&fetchAll=true'
              '&checkInFrom=2020-01-01'
              '&checkOutTo=2030-12-31';
          final urls = [
            baseUrl,
            '$baseUrl&status=archived',
          ];

          for (final url in urls) {
            final response = await http.get(Uri.parse(url), headers: _headers);
            if (response.statusCode >= 200 && response.statusCode < 300) {
              final decoded = jsonDecode(response.body);
              final records = decoded is List<dynamic>
                  ? decoded
                  : (decoded is Map ? (decoded['data'] as List? ?? []) : []);
              for (final r in records) {
                final id = r['id'] as String;
                if (seenIds.add(id)) {
                  allRemoteRecords.add(Map<String, dynamic>.from(r));
                }
              }
            }
          }
        }

        if (allRemoteRecords.isEmpty && lastSync != null) {
          // Delta sync with no changes — nothing to do
          debugPrint('📥 _pullFromBackend: no changes for $businessId');
          continue;
        }

        final remoteRecords = allRemoteRecords;
        final remoteIds = seenIds;

        // ── Handle deletions from delta response ────────────────────────
        // Records with isDeleted=true should be removed from local DB.
        final remoteDeletedIds = <String>{};
        for (final remote in remoteRecords) {
          if (remote['isDeleted'] == true) {
            remoteDeletedIds.add(remote['id'] as String);
          }
        }

        // 1. Prune local synced records that no longer exist on the cloud
        //    (only during full sync — delta sync only returns changed records
        //     so we can't infer absence means deletion).
        if (lastSync == null) {
          final localSynced = await db.query(
            LocalDatabase.tableGuestRecords,
            columns: ['id', 'local_updated_at'],
            where: 'business_id = ? AND sync_status = ?',
            whereArgs: [businessId, LocalDatabase.syncSynced],
          );

          final now = DateTime.now().toUtc();
          for (final local in localSynced) {
            final id = local['id'] as String;
            if (!remoteIds.contains(id)) {
              final localUpdatedAtStr = local['local_updated_at'] as String?;
              if (localUpdatedAtStr != null) {
                final updatedAt = DateTime.tryParse(localUpdatedAtStr);
                if (updatedAt != null &&
                    now.difference(updatedAt).inSeconds < 60) {
                  debugPrint('⏳ Skipping pruning for just-synced record $id (grace period)');
                  continue;
                }
              }

              debugPrint('🧹 _pullFromBackend: pruning local synced record $id (not found on cloud)');
              await db.delete(
                LocalDatabase.tableGuestRecords,
                where: 'id = ?',
                whereArgs: [id],
              );
              await db.delete(
                LocalDatabase.tableGuestRecordRooms,
                where: 'guest_record_id = ?',
                whereArgs: [id],
              );
            }
          }
        }

        // 2. Insert / Update records from cloud (skip any with pending changes).
        for (final remote in remoteRecords) {
          final recordId = remote['id'] as String;

          // If the server says this record is deleted, remove it locally.
          if (remoteDeletedIds.contains(recordId)) {
            debugPrint('🗑️ _pullFromBackend: deleting soft-deleted record $recordId');
            await db.delete(
              LocalDatabase.tableGuestRecords,
              where: 'id = ?',
              whereArgs: [recordId],
            );
            await db.delete(
              LocalDatabase.tableGuestRecordRooms,
              where: 'guest_record_id = ?',
              whereArgs: [recordId],
            );
            continue;
          }

          final pending = await db.query(
            LocalDatabase.tableGuestRecords,
            where: 'id = ? AND sync_status != ?',
            whereArgs: [recordId, LocalDatabase.syncSynced],
            limit: 1,
          );
          if (pending.isNotEmpty) {
            debugPrint('⏳ _pullFromBackend: skipping cloud record $recordId (has local pending changes)');
            continue;
          }

          // Upsert the guest record
          await db.insert(
            LocalDatabase.tableGuestRecords,
            _fromApiRecord(remote),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // Replace room junction rows
          await db.delete(
            LocalDatabase.tableGuestRecordRooms,
            where: 'guest_record_id = ?',
            whereArgs: [recordId],
          );

          final rooms = remote['rooms'] as List<dynamic>? ?? [];
          for (final r in rooms) {
            final roomId = r['id'] as String;
            await db.rawInsert(
              'INSERT OR IGNORE INTO ${LocalDatabase.tableLocalRooms} '
              '(id, business_id, room_number, capacity, room_status, sync_status) '
              'VALUES (?, ?, ?, ?, ?, ?)',
              [
                roomId,
                businessId,
                r['roomNumber'] ?? r['room_number'] ?? roomId.substring(0, 8),
                r['capacity'] ?? 1,
                'vacant',
                LocalDatabase.syncSynced,
              ],
            );
            await db.insert(
              LocalDatabase.tableGuestRecordRooms,
              {
                'id':               _generateUuid(),
                'guest_record_id':  recordId,
                'room_id':          roomId,
                'status':           r['status'] ?? 'active',
                'created_at':       remote['created_at'],
                'updated_at':       remote['updated_at'],
                'sync_status':      LocalDatabase.syncSynced,
                'local_updated_at': null,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        debugPrint('✅ _pullFromBackend: processed ${remoteRecords.length} record(s) for $businessId');
      } on SocketException catch (e) {
        debugPrint('🌐 _pullFromBackend: network lost — aborting ($e)');
        return;
      } catch (e) {
        debugPrint('❌ _pullFromBackend: failed for business $businessId — $e');
      }
    }

    // Persist the sync timestamp for the next delta cycle
    await _setLastSyncTimestamp(syncTimestamp);
    if (needsFull) {
      await _setLastFullSyncTimestamp(syncTimestamp);
      debugPrint('✅ _pullFromBackend: full sync timestamp saved');
    }
  }

  Future<void> _pullProfileAndBusiness() async {
    if (!await _canReachBackend()) return;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/profile'),
        headers: _headers,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final user = data['user'];
        final biz = data['business'];

        final db = await LocalDatabase.instance.database;

        if (user != null) {
          final data = {
            'id': user['id'],
            'username': user['username'],
            'full_name': user['full_name'],
            'email': user['email'],
            'phone': user['phone'],
            'role': user['role'],
            'created_at': user['created_at'],
            'updated_at': user['updated_at'],
          };
          final count = await db.update(
            LocalDatabase.tableLocalProfiles,
            data,
            where: 'id = ?',
            whereArgs: [user['id']],
          );
          if (count == 0) {
            data['password_hash'] = 'sync_dummy_hash';
            await db.insert(LocalDatabase.tableLocalProfiles, data);
          }
        }

        if (biz != null) {
          final data = {
            'id': biz['id'],
            'profile_id': biz['user_id'] ?? user['id'],
            'business_name': biz['business_name'],
            'permit_number': biz['permit_number'],
            'registration_number': biz['registration_number'],
            'street': biz['street'],
            'status': biz['status'],
            'region': biz['region'],
            'city_municipality': biz['city_municipality'],
            'province': biz['province'],
            'barangay': biz['barangay'],
            'tradename': biz['tradename'],
            'business_line': biz['business_line'] is String
                ? biz['business_line']
                : jsonEncode(biz['business_line']),
            'owner_first_name': biz['owner_first_name'],
            'owner_last_name': biz['owner_last_name'],
            'owner_middle_name': biz['owner_middle_name'],
            'business_type': biz['business_type'],
            'created_at': biz['created_at'],
            'updated_at': biz['updated_at'],
          };
          final count = await db.update(
            LocalDatabase.tableLocalBusinesses,
            data,
            where: 'id = ?',
            whereArgs: [biz['id']],
          );
          if (count == 0) {
            await db.insert(LocalDatabase.tableLocalBusinesses, data);
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ _pullProfileAndBusiness failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Attempts a background re-auth and, on success, schedules a fresh sync.
  Future<void> _tryRefreshToken() async {
    final s = SessionService.instance.current;
    if (s?.password == null) return;

    try {
      final success = await LoginApi().backgroundAuth(
        username: s!.username ?? s.email,
        password: s.password!,
      );
      if (success) {
        Future.delayed(const Duration(seconds: 1), sync);
      }
    } catch (e) {
      debugPrint('⚠️ _tryRefreshToken: $e');
    }
  }

  Future<bool> _canReachBackend() async {
    if (!ConnectivityService.instance.isOnline) return false;
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'), headers: _headers)
          .timeout(const Duration(seconds: 4));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<int> _countPending() async {
    if (kIsWeb) return 0;

    final db = await LocalDatabase.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM (
        SELECT id FROM ${LocalDatabase.tableGuestRecords} WHERE sync_status != ?
        UNION ALL
        SELECT id FROM ${LocalDatabase.tableLocalRooms} WHERE sync_status != ?
      )
      ''',
      [LocalDatabase.syncSynced, LocalDatabase.syncSynced],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  void _emit(SyncState state) {
    _state = state;
    _controller.add(state);
  }

  // ---------------------------------------------------------------------------
  // Delta Sync Timestamp Helpers
  // ---------------------------------------------------------------------------

  /// Returns the stored [lastSync] ISO timestamp, or `null` on first sync.
  Future<String?> _getLastSyncTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefKeyLastSync);
    } catch (_) {
      return null;
    }
  }

  /// Persists the [lastSync] ISO timestamp after a successful pull.
  Future<void> _setLastSyncTimestamp(String isoTimestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyLastSync, isoTimestamp);
    } catch (_) {}
  }

  /// Returns the stored [lastFullSync] ISO timestamp, or `null` if never.
  Future<String?> _getLastFullSyncTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefKeyLastFullSync);
    } catch (_) {
      return null;
    }
  }

  /// Persists the [lastFullSync] ISO timestamp after a full pull.
  Future<void> _setLastFullSyncTimestamp(String isoTimestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyLastFullSync, isoTimestamp);
    } catch (_) {}
  }

  /// Determines whether a full (non-delta) pull is needed.
  /// Returns `true` on first ever sync or if the last full sync was >24h ago.
  Future<bool> _needsFullSync() async {
    final lastFullSync = await _getLastFullSyncTimestamp();
    if (lastFullSync == null) return true;
    final parsed = DateTime.tryParse(lastFullSync);
    if (parsed == null) return true;
    return DateTime.now().toUtc().difference(parsed) >= _fullSyncInterval;
  }

  // ---------------------------------------------------------------------------
  // Payload Mappers
  // ---------------------------------------------------------------------------

  /// Converts a SQLite row + its room IDs into the JSON body expected by
  /// both POST /api/business/guest-entries and PUT /api/business/guest-records/:id.
  Map<String, dynamic> _toApiPayload(
    Map<String, dynamic> record,
    List<String> roomIds, {
    bool isCreate = false,
  }) {
    final actualCheckOut = record['actual_checkout'];
    final isCheckout = actualCheckOut != null &&
        (actualCheckOut as String).isNotEmpty;

    final payload = <String, dynamic>{
      'businessId':            record['business_id'],
      'checkIn':               record['check_in'],
      'checkOut':              record['check_out'],
      'actualCheckOut':        actualCheckOut,
      'totalGuests':           record['total_guests'],
      'purposeOfVisit':        record['purpose_of_visit'],
      'transportationMode':    record['transportation_mode'],
      'status':                record['status'],
      'leadCountry':           record['lead_country'],
      'leadMunicipality':      record['lead_city_municipality'],
      'leadProvince':          record['lead_province'],
      'leadNationality':       record['lead_nationality'],
      'leadPhilippinesRegion': record['lead_philippines_region'],
      'leadIsOverseas':        record['lead_is_overseas'] == 1,
      'leadBirthdate':         record['lead_birthdate'],
      'leadSex':               record['lead_sex'],
    };

    // Always include roomIds so the backend has them for both:
    // - Upsert branch: creates junction rows when the record doesn't exist yet
    //   (e.g. PUT arrives before the offline create's POST was pushed)
    // - Checkout branch: ignores roomIds and works from existing junction rows
    payload['roomIds'] = roomIds;

    return payload;
  }

  Map<String, dynamic> _fromApiRecord(Map<String, dynamic> row) {
    return {
      'id':                      row['id'],
      'business_id':             row['business_id'],
      'check_in':                row['check_in'],
      'check_out':               row['check_out'],
      'actual_checkout':         row['actual_check_out'],
      'length_of_stay':          row['length_of_stay'] ?? 1,
      'total_guests':            row['total_guests'],
      'purpose_of_visit':        row['purpose_of_visit'],
      'transportation_mode':     row['transportation_mode'],
      'lead_country':            row['lead_country'],
      'lead_city_municipality':  row['lead_city_municipality'],
      'lead_province':           row['lead_province'],
      'lead_nationality':        row['lead_nationality'],
      'lead_philippines_region': row['lead_philippines_region'],
      'lead_is_overseas':        (row['lead_is_overseas'] == true || row['lead_is_overseas'] == 1) ? 1 : 0,
      'lead_birthdate':          row['lead_birthdate'],
      'lead_sex':                row['lead_sex'],
      'status':                  row['status'] ?? 'active',
      'is_deleted':              (row['is_deleted'] == true) ? 1 : 0,
      'created_at':              row['created_at'],
      'updated_at':              row['updated_at'],
      'sync_status':             LocalDatabase.syncSynced,
      'local_updated_at':        null,
    };
  }

  String _generateUuid() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '$now-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  }
}