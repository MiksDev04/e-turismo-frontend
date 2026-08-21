import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'base_api.dart';

class VisitEntryResult {
  final bool success;
  final String? error;
  final bool syncedToCloud;

  const VisitEntryResult._({
    required this.success,
    this.error,
    this.syncedToCloud = false,
  });

  factory VisitEntryResult.ok({bool syncedToCloud = false}) =>
      VisitEntryResult._(success: true, syncedToCloud: syncedToCloud);

  factory VisitEntryResult.err(String error) =>
      VisitEntryResult._(success: false, error: error);
}

class VisitEntryData {
  const VisitEntryData({
    required this.visitDate,
    required this.guestCount,
    required this.isForeign,
    this.country,
    this.province,
    this.cityMunicipality,
    this.maleCount,
    this.femaleCount,
  });

  final DateTime visitDate;
  final int guestCount;
  final bool isForeign;
  final String? country;
  final String? province;
  final String? cityMunicipality;
  final int? maleCount;
  final int? femaleCount;

  Map<String, dynamic> toJson() {
    final visitDateStr =
        "${visitDate.year.toString().padLeft(4, '0')}-"
        "${visitDate.month.toString().padLeft(2, '0')}-"
        "${visitDate.day.toString().padLeft(2, '0')}";

    var male = maleCount ?? 0;
    var female = femaleCount ?? 0;
    if (male == 0 && female == 0) {
      male = (guestCount * 0.471).round();
      female = guestCount - male;
    } else if (male == 0) {
      male = guestCount - female;
    } else if (female == 0) {
      female = guestCount - male;
    }

    return {
      'visitDate': visitDateStr,
      'guestCount': guestCount,
      'isForeign': isForeign,
      'country': country,
      'province': province,
      'cityMunicipality': cityMunicipality,
      'maleCount': male,
      'femaleCount': female,
    };
  }
}

class AttractionVisitEntryApi extends BaseApi {
  AttractionVisitEntryApi();

  Future<String?> resolveAttractionId() async {
    final session =
        SessionService.instance.current ??
        await SessionService.instance.loadAndCache();
    return session?.attractionId;
  }

  // ---------------------------------------------------------------------------
  // Write-through save: SQLite first (pending_create), then push to the cloud
  // when online. Any cloud failure leaves the row pending for SyncService.
  // ---------------------------------------------------------------------------
  Future<VisitEntryResult> saveVisitEntry(VisitEntryData data) async {
    final online = ConnectivityService.instance.isOnline && hasToken;

    final attractionId = await resolveAttractionId();
    if (attractionId == null || attractionId.isEmpty) {
      return VisitEntryResult.err(
        'No attraction account associated with this user.',
      );
    }

    final entryId = _generateId();
    final payload = data.toJson()..['attractionId'] = attractionId;
    final now = DateTime.now().toUtc().toIso8601String();

    // ── Step 1: SQLite first — survives a mid-save disconnect ───────────────
    if (!kIsWeb) {
      try {
        await _insertLocalEntry(
          entryId: entryId,
          attractionId: attractionId,
          payload: payload,
          now: now,
        );
      } catch (e) {
        debugPrint('❌ saveVisitEntry: local write failed — $e');
        return VisitEntryResult.err(
          'Failed to save visit entry. Please try again.',
        );
      }
    }

    if (!online) {
      debugPrint('💾 saveVisitEntry: offline — entry $entryId queued for sync');
      return VisitEntryResult.ok();
    }

    // ── Step 2: Push to Node API ─────────────────────────────────────────────
    try {
      final response = await post(
        '/api/attraction/visit-entry/visit-entries',
        payload..['id'] = entryId,
      );

      if (response.statusCode == 409) {
        debugPrint('⚠️ saveVisitEntry: 409 — create already landed, marking synced');
        await _markSynced(entryId);
        return VisitEntryResult.ok(syncedToCloud: true);
      }

      handleResponse(response);

      await _markSynced(entryId, responseBody: response.body);
      return VisitEntryResult.ok(syncedToCloud: true);
    } catch (e) {
      debugPrint('⚠️ saveVisitEntry: cloud push failed — queued for sync ($e)');
      return VisitEntryResult.ok();
    }
  }

  // ---------------------------------------------------------------------------
  // SQLite helpers
  // ---------------------------------------------------------------------------

  Future<void> _insertLocalEntry({
    required String entryId,
    required String attractionId,
    required Map<String, dynamic> payload,
    required String now,
  }) async {
    final db = await LocalDatabase.instance.database;
    final session = SessionService.instance.current;

    // Ensure the parent rows exist so the foreign keys are satisfied.
    if (session != null) {
      await db.insert(
        LocalDatabase.tableLocalProfiles,
        {
          'id': session.userId,
          'username': session.username ?? session.email,
          'full_name': session.fullName,
          'email': session.email,
          'phone': session.phone,
          'role': session.role,
          'password_hash': 'temp_hash',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      await db.insert(
        LocalDatabase.tableLocalAttractions,
        {
          'id': attractionId,
          'profile_id': session.userId,
          'attraction_name': session.attractionName,
          'attraction_type': session.attractionType != null
              ? jsonEncode(session.attractionType)
              : null,
          'street': session.street,
          'barangay': session.barangay,
          'status': session.status,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await db.insert(
      LocalDatabase.tableVisitEntries,
      {
        'id':                entryId,
        'attraction_id':     attractionId,
        'visit_date':        payload['visitDate'],
        'guest_count':       payload['guestCount'],
        'male_count':        payload['maleCount'],
        'female_count':      payload['femaleCount'],
        'country':           payload['country'],
        'province':          payload['province'],
        'city_municipality': payload['cityMunicipality'],
        'nationality':       null,
        'created_at':        now,
        'updated_at':        now,
        'sync_status':       LocalDatabase.syncPendingCreate,
        'local_updated_at':  now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint(
      '💾 SQLite: saved visit entry $entryId (${LocalDatabase.syncPendingCreate})',
    );
  }

  Future<void> _markSynced(String localId, {String? responseBody}) async {
    final db = await LocalDatabase.instance.database;
    var id = localId;

    // The backend generates its own UUID — remap the local primary key
    // when the server kept a different one.
    if (responseBody != null && responseBody.isNotEmpty) {
      try {
        final body = jsonDecode(responseBody);
        final serverId =
            body is Map ? body['visitEntryId'] as String? : null;
        if (serverId != null && serverId.isNotEmpty && serverId != localId) {
          await db.update(
            LocalDatabase.tableVisitEntries,
            {'id': serverId},
            where: 'id = ?',
            whereArgs: [localId],
          );
          id = serverId;
        }
      } catch (_) {}
    }

    await db.update(
      LocalDatabase.tableVisitEntries,
      {
        'sync_status':      LocalDatabase.syncSynced,
        'local_updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where:     'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // UUID generator
  // ---------------------------------------------------------------------------
  String _generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
