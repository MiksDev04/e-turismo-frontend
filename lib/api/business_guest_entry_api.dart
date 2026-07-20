import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'base_api.dart';

class GuestEntryResult {
  final bool success;
  final String? error;
  final bool syncedToCloud;

  const GuestEntryResult._({
    required this.success,
    this.error,
    this.syncedToCloud = false,
  });

  factory GuestEntryResult.ok({bool syncedToCloud = false}) =>
      GuestEntryResult._(success: true, syncedToCloud: syncedToCloud);

  factory GuestEntryResult.err(String error) =>
      GuestEntryResult._(success: false, error: error);
}

class RoomInfo {
  const RoomInfo({
    required this.id,
    required this.roomNumber,
    required this.capacity,
    this.status = 'vacant',
  });

  final String id;
  final String roomNumber;
  final int capacity;
  final String status;

  bool get isReserved => status == 'reserved';
}

class GuestEntryData {
  const GuestEntryData({
    required this.businessId,
    required this.checkIn,
    required this.checkOut,
    required this.totalGuests,
    required this.roomIds,
    required this.purposeOfVisit,
    required this.transportationMode,
    this.leadCountry,
    this.leadMunicipality,
    this.leadProvince,
    this.leadNationality,
    this.leadPhilippinesRegion,
    this.leadIsOverseas = false,
    this.leadBirthdate,
    this.leadSex,
  });

  final String businessId;
  final DateTime checkIn;
  final DateTime checkOut;
  final int totalGuests;
  final List<String> roomIds;
  final String purposeOfVisit;
  final String transportationMode;
  final String? leadCountry;
  final String? leadMunicipality;
  final String? leadProvince;
  final String? leadNationality;
  final String? leadPhilippinesRegion;
  final bool leadIsOverseas;
  final DateTime? leadBirthdate;
  final String? leadSex;
}

class BusinessGuestEntryApi extends BaseApi {
  // ── Fetch business ID ──────────────────────────────────────────────────────

  Future<String?> fetchBusinessId() async {
    return SessionService.instance.current?.businessId;
  }

  // ── Fetch vacant rooms for a business ──────────────────────────────────────

  Future<List<RoomInfo>> fetchVacantRooms(String businessId) async {
    if (!ConnectivityService.instance.isOnline || !hasToken) {
      // Offline: return from local cache
      return _fetchVacantRoomsLocal(businessId);
    }

    try {
      final response = await get('/api/business/vacant-rooms?businessId=$businessId');
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] as List<dynamic>? ?? [];
        final rooms = data
            .map((r) => RoomInfo(
                  id: r['id'] as String,
                  roomNumber: r['roomNumber'] as String,
                  capacity: r['capacity'] as int,
                  status: r['status'] as String? ?? 'vacant',
                ))
            .toList();

        // Cache rooms locally for offline use
        await _cacheRoomsLocally(businessId, rooms);
        return rooms;
      }
      throw Exception('Failed to fetch rooms: ${response.statusCode}');
    } catch (e) {
      debugPrint('⚠️ fetchVacantRooms: API failed, falling back to local cache — $e');
      return _fetchVacantRoomsLocal(businessId);
    }
  }

  Future<List<RoomInfo>> _fetchVacantRoomsLocal(String businessId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      LocalDatabase.tableLocalRooms,
      where: 'business_id = ? AND room_status IN (?, ?)',
      whereArgs: [businessId, 'vacant', 'reserved'],
      orderBy: 'room_number',
    );
    return rows
        .map((r) => RoomInfo(
              id: r['id'] as String,
              roomNumber: r['room_number'] as String,
              capacity: r['capacity'] as int,
              status: r['room_status'] as String? ?? 'vacant',
            ))
        .toList();
  }

  Future<void> _cacheRoomsLocally(String businessId, List<RoomInfo> rooms) async {
    if (kIsWeb) return;
    try {
      final db = await LocalDatabase.instance.database;
      // Only insert rooms that don't already exist locally.
      // Do NOT delete existing rooms or junction rows — that would destroy
      // occupied-room data and guest_record_rooms relationships needed for
      // offline display.
      for (final room in rooms) {
        await db.insert(
          LocalDatabase.tableLocalRooms,
          {
            'id':               room.id,
            'business_id':      businessId,
            'room_number':      room.roomNumber,
            'capacity':         room.capacity,
            'room_status':      'vacant',
            'created_at':       DateTime.now().toUtc().toIso8601String(),
            'updated_at':       DateTime.now().toUtc().toIso8601String(),
            'sync_status':      LocalDatabase.syncSynced,
            'local_updated_at': null,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    } catch (e) {
      debugPrint('⚠️ _cacheRoomsLocally: $e');
    }
  }

  // ── Save guest entry ──────────────────────────────────────────────────────

  Future<GuestEntryResult> saveGuestEntry(GuestEntryData data) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      return _saveOnline(data);
    } else {
      return _saveOffline(data);
    }
  }

  // ---------------------------------------------------------------------------
  // ONLINE
  // ---------------------------------------------------------------------------
  Future<GuestEntryResult> _saveOnline(GuestEntryData data) async {
    final guestRecordId = _generateId();
    final checkInStr  = _formatDate(data.checkIn);
    final checkOutStr = _formatDate(data.checkOut);
    final now         = DateTime.now().toUtc().toIso8601String();
    final leadBirthStr = data.leadBirthdate != null ? _formatDate(data.leadBirthdate!) : null;

    // ── Step 1: SQLite first ────────────────────────────────────────────────
    if (!kIsWeb) {
      try {
        await _upsertLocalRecord(
          recordId:           guestRecordId,
          businessId:         data.businessId,
          checkIn:            checkInStr,
          checkOut:           checkOutStr,
          totalGuests:        data.totalGuests,
          purposeOfVisit:     data.purposeOfVisit,
          transportationMode: data.transportationMode,
          leadCountry:        data.leadCountry,
          leadMunicipality:   data.leadMunicipality,
          leadProvince:       data.leadProvince,
          leadNationality:    data.leadNationality,
          leadRegion:         data.leadPhilippinesRegion,
          leadIsOverseas:     data.leadIsOverseas,
          leadBirthdate:      leadBirthStr,
          leadSex:            data.leadSex,
          roomIds:            data.roomIds,
          createdAt:          now,
          syncStatus:         LocalDatabase.syncPendingCreate,
          localUpdatedAt:     now,
        );
      } catch (e) {
        debugPrint('❌ _saveOnline: local write failed — $e');
        return GuestEntryResult.err('Failed to save guest entry. Please try again.');
      }
    }

    // ── Step 2: Push to Node API ─────────────────────────────────────────────
    try {
      final payload = {
        'id': guestRecordId,
        'businessId': data.businessId,
        'checkIn': checkInStr,
        'checkOut': checkOutStr,
        'totalGuests': data.totalGuests,
        'roomIds': data.roomIds,
        'purposeOfVisit': data.purposeOfVisit,
        'transportationMode': data.transportationMode,
        'leadCountry': data.leadCountry,
        'leadMunicipality': data.leadMunicipality,
        'leadProvince': data.leadProvince,
        'leadNationality': data.leadNationality,
        'leadPhilippinesRegion': data.leadPhilippinesRegion,
        'leadIsOverseas': data.leadIsOverseas,
        'leadBirthdate': leadBirthStr,
        'leadSex': data.leadSex,
      };

      final response = await post('/api/business/guest-entries', payload);

      if (response.statusCode != 201) {
        throw Exception('Failed to save to cloud: ${response.body}');
      }

      // ── Step 3: Mark synced in SQLite ──────────────────────────────────────
      if (!kIsWeb) {
        final db = await LocalDatabase.instance.database;
        await db.update(
          LocalDatabase.tableGuestRecords,
          {
            'sync_status':      LocalDatabase.syncSynced,
            'local_updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where:     'id = ?',
          whereArgs: [guestRecordId],
        );
      }

      return GuestEntryResult.ok(syncedToCloud: true);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        debugPrint('⚠️ _saveOnline: Unauthorized (401). Queuing for sync.');
        return GuestEntryResult.ok(syncedToCloud: false);
      }
      debugPrint('⚠️ _saveOnline: Node API request failed, queued for sync — $e');
      return GuestEntryResult.ok(syncedToCloud: false);
    }
  }

  // ---------------------------------------------------------------------------
  // OFFLINE
  // ---------------------------------------------------------------------------
  Future<GuestEntryResult> _saveOffline(GuestEntryData data) async {
    try {
      final guestRecordId = _generateId();
      final checkInStr    = _formatDate(data.checkIn);
      final checkOutStr   = _formatDate(data.checkOut);
      final now           = DateTime.now().toUtc().toIso8601String();
      final leadBirthStr  = data.leadBirthdate != null ? _formatDate(data.leadBirthdate!) : null;

      await _upsertLocalRecord(
        recordId:           guestRecordId,
        businessId:         data.businessId,
        checkIn:            checkInStr,
        checkOut:           checkOutStr,
        totalGuests:        data.totalGuests,
        purposeOfVisit:     data.purposeOfVisit,
        transportationMode: data.transportationMode,
        leadCountry:        data.leadCountry,
        leadMunicipality:   data.leadMunicipality,
        leadProvince:       data.leadProvince,
        leadNationality:    data.leadNationality,
        leadRegion:         data.leadPhilippinesRegion,
        leadIsOverseas:     data.leadIsOverseas,
        leadBirthdate:      leadBirthStr,
        leadSex:            data.leadSex,
        roomIds:            data.roomIds,
        createdAt:          now,
        syncStatus:         LocalDatabase.syncPendingCreate,
        localUpdatedAt:     now,
      );

      return GuestEntryResult.ok();
    } catch (e) {
      debugPrint('❌ saveGuestEntry (offline) error: $e');
      return GuestEntryResult.err('Failed to save guest entry locally. Please try again.');
    }
  }

  // ---------------------------------------------------------------------------
  // SQLite helpers
  // ---------------------------------------------------------------------------

  Future<void> _upsertLocalRecord({
    required String recordId,
    required String businessId,
    required String checkIn,
    required String checkOut,
    required int totalGuests,
    required String purposeOfVisit,
    required String transportationMode,
    String? leadCountry,
    String? leadMunicipality,
    String? leadProvince,
    String? leadNationality,
    String? leadRegion,
    bool leadIsOverseas = false,
    String? leadBirthdate,
    String? leadSex,
    List<String>? roomIds,
    String? createdAt,
    required String syncStatus,
    required String? localUpdatedAt,
  }) async {
    final db = await LocalDatabase.instance.database;
    final current = SessionService.instance.current;

    // Compute length_of_stay from dates
    final dIn  = DateTime.parse(checkIn);
    final dOut = DateTime.parse(checkOut);
    final lengthOfStay = dOut.difference(dIn).inDays.clamp(1, 999);

    // Ensure the profile and business exist locally to satisfy foreign key constraints
    if (current != null) {
      await db.insert(
        LocalDatabase.tableLocalProfiles,
        {
          'id': current.userId,
          'username': current.username ?? current.email,
          'full_name': current.fullName,
          'email': current.email,
          'phone': current.phone,
          'role': current.role,
          'password_hash': 'temp_hash',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      await db.insert(
        LocalDatabase.tableLocalBusinesses,
        {
          'id': businessId,
          'profile_id': current.userId,
          'business_name': current.businessName ?? 'Unknown',
          'status': current.status ?? 'approved',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    // Ensure local_rooms entries exist for the room IDs being assigned,
    // so the junction table foreign key won't fail. If the room already
    // exists locally (from a prior sync pull) the INSERT OR IGNORE is a no-op
    // and preserves the real room_number/capacity/status.
    if (roomIds != null) {
      for (final roomId in roomIds) {
        await db.rawInsert(
          'INSERT OR IGNORE INTO ${LocalDatabase.tableLocalRooms} '
          '(id, business_id, room_number, capacity, room_status, sync_status, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            roomId,
            businessId,
            'Room ${roomId.substring(0, 8)}',
            1,
            'occupied',
            LocalDatabase.syncSynced,
            createdAt,
            createdAt,
          ],
        );
      }
    }

    await db.insert(
      LocalDatabase.tableGuestRecords,
      {
        'id':                      recordId,
        'business_id':             businessId,
        'check_in':                checkIn,
        'check_out':               checkOut,
        'length_of_stay':          lengthOfStay,
        'total_guests':            totalGuests,
        'purpose_of_visit':        purposeOfVisit,
        'transportation_mode':     transportationMode,
        'lead_country':            leadCountry,
        'lead_city_municipality':  leadMunicipality,
        'lead_province':           leadProvince,
        'lead_nationality':        leadNationality,
        'lead_philippines_region': leadRegion,
        'lead_is_overseas':        leadIsOverseas ? 1 : 0,
        'lead_birthdate':          leadBirthdate,
        'lead_sex':                leadSex?.toLowerCase(),
        'status':                  'active',
        'is_deleted':              0,
        'created_at':              createdAt,
        'updated_at':              createdAt,
        'sync_status':             syncStatus,
        'local_updated_at':        localUpdatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Write room assignments to junction table
    if (roomIds != null && roomIds.isNotEmpty) {
      // Clear old links for this record
      await db.delete(
        LocalDatabase.tableGuestRecordRooms,
        where: 'guest_record_id = ?',
        whereArgs: [recordId],
      );
      for (final roomId in roomIds) {
        final junctionId = _generateId();
        await db.insert(
          LocalDatabase.tableGuestRecordRooms,
          {
            'id':               junctionId,
            'guest_record_id':  recordId,
            'room_id':          roomId,
            'status':           'active',
            'created_at':       createdAt,
            'updated_at':       localUpdatedAt,
            'sync_status':      syncStatus,
            'local_updated_at': localUpdatedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    debugPrint('💾 SQLite: saved record $recordId (status: $syncStatus, business: $businessId)');
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

  // ---------------------------------------------------------------------------
  // Value helpers
  // ---------------------------------------------------------------------------

  String _formatDate(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
