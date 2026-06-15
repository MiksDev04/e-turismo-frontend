import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
    Map<String, dynamic>? business,
  }) async {
    final db = await LocalDatabase.instance.database;
    final hash = _hashPassword(password, id);

    await db.transaction((txn) async {
      await txn.insert(
        LocalDatabase.tableLocalProfiles,
        {
          'id': id,
          'username': username,
          'full_name': fullName,
          'email': email,
          'phone': phone,
          'role': role,
          'password_hash': hash,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (business != null) {
        await txn.insert(
          LocalDatabase.tableLocalBusinesses,
          {
            'id': business['id'],
            'profile_id': id,
            'business_name': business['business_name'],
            'status': business['status'],
            'permit_number': business['permit_number'],
            'registration_number': business['registration_number'],
            'street': business['street'],
            'total_rooms': business['total_rooms'],
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
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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
      where: 'username = ?',
      whereArgs: [username],
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
// SYNC SERVICE
// =============================================================================

class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  String get _baseUrl {
    if (kIsWeb) {
      return dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
    } else if (Platform.isAndroid) {
      return dotenv.env['ANDROID_BACKEND_URL'] ?? 'http://10.0.2.2:3000';
    } else {
      return dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000';
    }
  }

  Map<String, String> get _headers {
    final token = SessionService.instance.current?.token;
    return {
      'Content-Type': 'application/json',
      'x-api-key': dotenv.env['API_KEY'] ?? '',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  final StreamController<SyncState> _controller =
      StreamController<SyncState>.broadcast();
  Stream<SyncState> get syncStateStream => _controller.stream;

  SyncState _state = const SyncState(status: SyncStatus.idle);
  SyncState get currentState => _state;

  static const _syncDelay = Duration(milliseconds: 500);

  void listenForConnectivity() {
    ConnectivityService.instance.onConnectivityChanged.listen((isOnline) async {
      final session = SessionService.instance.current;
      if (session == null || session.role != 'business') return;

      if (isOnline) {
        // ── Auto-Cloud-Upgrade ──────────────────────────────────────────────
        // If we are online but have no token, attempt to get one using stored password.
        if (session.password != null) {
          debugPrint(
            '☁️ SyncService: Online detected. Refreshing token before sync...',
          );
          try {
            final success = await LoginApi().backgroundAuth(
              username: session.username ?? session.email,
              password: session.password!,
            );
            if (success) {
              debugPrint('✅ SyncService: Auto-auth successful.');
            } else {
              debugPrint('❌ SyncService: Auto-auth failed.');
            }
          } catch (e) {
            debugPrint('⚠️ SyncService: Auto-auth error: $e');
          }
        }

        try {
          // Fetch profile and business to ensure SQLite has the business record
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
            await _pullForBusiness(businessId);
          }
        } catch (e) {
          debugPrint('⚠️ listenForConnectivity: initial pulls failed: $e');
        }

        await _clearOfflineSessionFlag();
        // Give a small delay for the state to settle before full sync
        Future.delayed(_syncDelay, sync);
      }
    });
  }

  Future<void> _clearOfflineSessionFlag() async {
    final current = SessionService.instance.current;
    if (current == null || !current.isOfflineSession) return;

    final updated = SessionData(
      userId: current.userId,
      fullName: current.fullName,
      username: current.username,
      email: current.email,
      phone: current.phone,
      role: current.role,
      isOfflineSession: false,
      businessId: current.businessId,
      businessName: current.businessName,
      permitNumber: current.permitNumber,
      registrationNumber: current.registrationNumber,
      street: current.street,
      totalRooms: current.totalRooms,
      permitFileUrl: current.permitFileUrl,
      validIdUrl: current.validIdUrl,
      businessType: current.businessType,
      status: current.status,
      remarks: current.remarks,
      region: current.region,
      cityMunicipality: current.cityMunicipality,
      province: current.province,
      barangay: current.barangay,
      tradename: current.tradename,
      businessLine: current.businessLine,
      ownerFirstName: current.ownerFirstName,
      ownerLastName: current.ownerLastName,
      ownerMiddleName: current.ownerMiddleName,
    );

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

    // Proceed with sync even if no token is available (the backend may allow it or BaseApi handles it)
    _emit(const SyncState(status: SyncStatus.syncing));

    try {
      await _pullProfileAndBusiness();
      await _pushPendingCreates();
      await _pushPendingUpdates();
      await _pullFromBackend();
      await _pullMessages(); // NEW

      final remaining = await _countPending();
      _emit(SyncState(status: SyncStatus.synced, pendingCount: remaining));
    } catch (e) {
      _emit(
        SyncState(
          status: SyncStatus.error,
          errorMessage: e.toString(),
          pendingCount: await _countPending(),
        ),
      );
    }
  }

  Future<int> getPendingCount() => _countPending();

  Future<void> _pullMessages() async {
    final current = SessionService.instance.current;
    if (current == null || current.businessId == null) return;

    final businessId = current.businessId!;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/messages/business/inbox?includeArchived=true'),
        headers: _headers,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final List<dynamic> rows = jsonDecode(response.body);
        final db = await LocalDatabase.instance.database;

        await db.transaction((txn) async {
          for (final row in rows) {
            final msg = row['message'] as Map<String, dynamic>;
            final recipientId = row['id'] as String;
            final messageId = row['message_id'] as String;

            // 1. Insert message
            await txn.insert(
              LocalDatabase.tableLocalMessages,
              {
                'id': messageId,
                'sender_id': msg['sender_id'],
                'message_type': msg['message_type'],
                'subject': msg['subject'],
                'content': msg['content'],
                'is_broadcast':
                    (msg['is_broadcast'] == true || msg['is_broadcast'] == 1)
                    ? 1
                    : 0,
                'created_at': msg['created_at'],
                'sender_name': msg['sender']?['full_name'],
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            // 2. Insert recipient entry
            await txn.insert(
              LocalDatabase.tableMessageRecipients,
              {
                'id': recipientId,
                'message_id': messageId,
                'business_id': businessId,
                'status': row['status'],
                'is_read': (row['is_read'] == true || row['is_read'] == 1)
                    ? 1
                    : 0,
                'read_at': row['read_at'],
                'created_at': row['created_at'],
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        });
        debugPrint('✅ _pullMessages: synced ${rows.length} messages');
      }
    } catch (e) {
      debugPrint('⚠️ _pullMessages failed: $e');
    }
  }

  Future<void> _pushPendingCreates() async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pushPendingCreates: skipped — Backend unreachable');
      return;
    }

    final db = await LocalDatabase.instance.database;

    final records = await db.query(
      LocalDatabase.tableGuestRecords,
      where: 'sync_status = ?',
      whereArgs: [LocalDatabase.syncPendingCreate],
    );

    for (final record in records) {
      final recordId = record['id'] as String;

      try {
        final breakdowns = await db.query(
          LocalDatabase.tableGuestBreakdowns,
          where: 'guest_record_id = ?',
          whereArgs: [recordId],
        );

        final payload = _toApiPayload(record, breakdowns);
        payload['id'] = recordId;

        final response = await http.post(
          Uri.parse('$_baseUrl/api/business/guest-entries'),
          headers: _headers,
          body: jsonEncode(payload),
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
          debugPrint('✅ _pushPendingCreates: pushed $recordId');
        } else if (response.statusCode == 401) {
          debugPrint(
            '🔐 _pushPendingCreates: 401 — token expired, refreshing and aborting for retry',
          );
          final s = SessionService.instance.current;
          if (s?.password != null) {
            await LoginApi().backgroundAuth(
              username: s!.username ?? s.email,
              password: s.password!,
            );
          }
          return; // Stop this batch — next sync will use the fresh token
        } else {
          debugPrint(
            '❌ _pushPendingCreates: failed for $recordId — ${response.body}',
          );
        }
      } on SocketException catch (e) {
        debugPrint('🌐 _pushPendingCreates: network lost — aborting ($e)');
        return;
      } catch (e) {
        debugPrint('❌ _pushPendingCreates: failed for $recordId — $e');
      }
    }
  }

  Future<void> _pushPendingUpdates() async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pushPendingUpdates: skipped — Backend unreachable');
      return;
    }

    final db = await LocalDatabase.instance.database;

    final records = await db.query(
      LocalDatabase.tableGuestRecords,
      where: 'sync_status = ?',
      whereArgs: [LocalDatabase.syncPendingUpdate],
    );

    for (final record in records) {
      final recordId = record['id'] as String;

      try {
        final breakdowns = await db.query(
          LocalDatabase.tableGuestBreakdowns,
          where: 'guest_record_id = ?',
          whereArgs: [recordId],
        );

        final payload = _toApiPayload(record, breakdowns);

        final response = await http.put(
          Uri.parse('$_baseUrl/api/business/guest-records/$recordId'),
          headers: _headers,
          body: jsonEncode(payload),
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
          debugPrint('✅ _pushPendingUpdates: pushed $recordId');
        } else if (response.statusCode == 401) {
          debugPrint(
            '🔐 _pushPendingUpdates: 401 — token expired, refreshing and aborting for retry',
          );
          final s = SessionService.instance.current;
          if (s?.password != null) {
            await LoginApi().backgroundAuth(
              username: s!.username ?? s.email,
              password: s.password!,
            );
          }
          return;
        } else {
          debugPrint(
            '❌ _pushPendingUpdates: failed for $recordId — ${response.body}',
          );
        }
      } on SocketException catch (e) {
        debugPrint('🌐 _pushPendingUpdates: network lost — aborting ($e)');
        return;
      } catch (e) {
        debugPrint('❌ _pushPendingUpdates: failed for $recordId — $e');
      }
    }
  }

  Future<void> _pullFromBackend() async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pullFromBackend: skipped — Backend unreachable');
      return;
    }

    final db = await LocalDatabase.instance.database;

    final businesses = await db.query(
      LocalDatabase.tableLocalBusinesses,
      columns: ['id'],
    );

    for (final business in businesses) {
      final businessId = business['id'] as String;

      try {
        final response = await http.get(
          Uri.parse(
            '$_baseUrl/api/business/guest-records?businessId=$businessId',
          ),
          headers: _headers,
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final remoteRecords = jsonDecode(response.body) as List<dynamic>;
          final remoteIds = remoteRecords.map((r) => r['id'] as String).toSet();

          // 1. Prune local records that were deleted on the Cloud
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
              // SAFETY: Don't prune if the record was updated/synced in the last 60 seconds.
              final localUpdatedAtStr = local['local_updated_at'] as String?;
              if (localUpdatedAtStr != null) {
                final updatedAt = DateTime.tryParse(localUpdatedAtStr);
                if (updatedAt != null &&
                    now.difference(updatedAt).inSeconds < 60) {
                  debugPrint(
                    '⏳ Skipping pruning for just-synced record $id (grace period)',
                  );
                  continue;
                }
              }

              debugPrint(
                '🧹 Pruning local synced record $id (not found on cloud)',
              );
              await db.delete(
                LocalDatabase.tableGuestRecords,
                where: 'id = ?',
                whereArgs: [id],
              );
              await db.delete(
                LocalDatabase.tableGuestBreakdowns,
                where: 'guest_record_id = ?',
                whereArgs: [id],
              );
            }
          }

          // 2. Insert / Update from Cloud
          for (final remote in remoteRecords) {
            final recordId = remote['id'] as String;

            final pending = await db.query(
              LocalDatabase.tableGuestRecords,
              where: 'id = ? AND sync_status != ?',
              whereArgs: [recordId, LocalDatabase.syncSynced],
              limit: 1,
            );
            if (pending.isNotEmpty) continue;

            await db.insert(
              LocalDatabase.tableGuestRecords,
              _fromApiRecord(remote as Map<String, dynamic>),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            await db.delete(
              LocalDatabase.tableGuestBreakdowns,
              where: 'guest_record_id = ?',
              whereArgs: [recordId],
            );

            final breakdowns =
                remote['guest_breakdowns'] as List<dynamic>? ?? [];

            for (final b in breakdowns) {
              await db.insert(
                LocalDatabase.tableGuestBreakdowns,
                _fromApiBreakdown(b as Map<String, dynamic>, recordId),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
      } on SocketException catch (e) {
        debugPrint('🌐 _pullFromBackend: network lost — aborting ($e)');
        return;
      } catch (e) {
        debugPrint('❌ _pullFromBackend: failed for business $businessId — $e');
      }
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
          await db.insert(
            LocalDatabase.tableLocalProfiles,
            {
              'id': user['id'],
              'username': user['username'],
              'full_name': user['full_name'],
              'email': user['email'],
              'phone': user['phone'],
              'role': user['role'],
              'password_hash': 'sync_dummy_hash',
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }

        if (biz != null) {
          await db.insert(
            LocalDatabase.tableLocalBusinesses,
            {
              'id': biz['id'],
              'profile_id': biz['user_id'] ?? user['id'],
              'business_name': biz['business_name'],
              'permit_number': biz['permit_number'],
              'registration_number': biz['registration_number'],
              'street': biz['street'],
              'total_rooms': biz['total_rooms'],
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
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ _pullProfileAndBusiness failed: $e');
    }
  }

  Future<void> _pullForBusiness(String businessId) async {
    if (!await _canReachBackend()) {
      debugPrint('⏭ _pullForBusiness: skipped — Backend unreachable');
      return;
    }

    final db = await LocalDatabase.instance.database;

    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/api/business/guest-records?businessId=$businessId',
        ),
        headers: _headers,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final remoteRecords = jsonDecode(response.body) as List<dynamic>;

        for (final remote in remoteRecords) {
          final recordId = remote['id'] as String;

          final pending = await db.query(
            LocalDatabase.tableGuestRecords,
            where: 'id = ? AND sync_status != ?',
            whereArgs: [recordId, LocalDatabase.syncSynced],
            limit: 1,
          );
          if (pending.isNotEmpty) continue;

          await db.insert(
            LocalDatabase.tableGuestRecords,
            _fromApiRecord(remote as Map<String, dynamic>),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          await db.delete(
            LocalDatabase.tableGuestBreakdowns,
            where: 'guest_record_id = ?',
            whereArgs: [recordId],
          );

          final breakdowns = remote['guest_breakdowns'] as List<dynamic>? ?? [];

          for (final b in breakdowns) {
            await db.insert(
              LocalDatabase.tableGuestBreakdowns,
              _fromApiBreakdown(b as Map<String, dynamic>, recordId),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    } on SocketException catch (e) {
      debugPrint('🌐 _pullForBusiness: network lost — aborting ($e)');
      return;
    } catch (e) {
      debugPrint('❌ _pullForBusiness: failed for business $businessId — $e');
    }
  }

  Future<bool> _canReachBackend() async {
    return ConnectivityService.instance.isOnline;
  }

  Future<int> _countPending() async {
    if (kIsWeb) return 0;

    final db = await LocalDatabase.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM ${LocalDatabase.tableGuestRecords}
      WHERE sync_status != ?
      ''',
      [LocalDatabase.syncSynced],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  void _emit(SyncState state) {
    _state = state;
    _controller.add(state);
  }

  Map<String, dynamic> _toApiPayload(
    Map<String, dynamic> record,
    List<Map<String, dynamic>> breakdowns,
  ) {
    return {
      'businessId': record['business_id'],
      'checkIn': record['check_in'],
      'checkOut': record['check_out'],
      'totalGuests': record['total_guests'],
      'roomsOccupied': record['rooms_occupied'],
      'purposeOfVisit': record['purpose_of_visit'],
      'transportationMode': record['transportation_mode'],
      'status': record['status'],
      'breakdowns': breakdowns
          .map(
            (b) => {
              'isOverseas': b['is_overseas'] == 1,
              'country': b['country'],
              'nationality': b['nationality'],
              'philippinesRegion': b['philippines_region'],
              'sex': b['sex'],
              'ageGroup': b['age_group'],
              'count': b['count'],
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> _fromApiRecord(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'business_id': row['business_id'],
      'check_in': row['check_in'],
      'check_out': row['check_out'],
      'total_guests': row['total_guests'],
      'rooms_occupied': row['rooms_occupied'],
      'purpose_of_visit': row['purpose_of_visit'],
      'transportation_mode': row['transportation_mode'],
      'status': row['status'] ?? 'active',
      'is_deleted': (row['is_deleted'] == true) ? 1 : 0,
      'created_at': row['created_at'],
      'sync_status': LocalDatabase.syncSynced,
      'local_updated_at': null,
    };
  }

  Map<String, dynamic> _fromApiBreakdown(
    Map<String, dynamic> row,
    String recordId,
  ) {
    return {
      'id': row['id'],
      'guest_record_id': row['guest_record_id'] ?? recordId,
      'country': row['country'],
      'philippines_region': row['philippines_region'],
      'nationality': row['nationality'],
      'sex': row['sex'],
      'age_group': row['age_group'],
      'count': row['count'],
      'is_overseas': (row['is_overseas'] == true) ? 1 : 0,
    };
  }
}
