import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'package:app/ui/business/pages/business_guest_records_page.dart';
import 'base_api.dart';

// ─── Result Wrapper ───────────────────────────────────────────────────────────

class ApiResult<T> {
  const ApiResult.success(this.data) : error = null;
  const ApiResult.failure(this.error) : data = null;

  final T? data;
  final String? error;

  bool get isSuccess => error == null;
}

// ─── Business Guest Record API ────────────────────────────────────────────────

class BusinessGuestRecordApi extends BaseApi {
  // ── Fetch Business ID ─────────────────────────────────────────────────────
  //
  // Fallback priority (both online and offline):
  //   1. Node API  (only when online — freshest source of truth)
  //   2. SessionService cache  (always available after any login type)
  //   3. SQLite local_businesses table  (populated by SyncService pull)
  //
  // This triple-fallback means a mid-session connectivity toggle never causes
  // "Business account not found" — we always have at least the cached value.

  Future<String?> fetchBusinessId() async {
    if (!ConnectivityService.instance.isOnline) {
      // ── Offline path ──────────────────────────────────────────────────────
      debugPrint('fetchBusinessId: offline — using local fallbacks');
      return _sessionId() ?? await _localDbId();
    }

    // ── Online path: try HTTP first ────────────────────────────────────
    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      final id = data?['business']?['id']?.toString();
      if (id != null) {
        debugPrint('fetchBusinessId: resolved from Node API → $id');
        return id;
      }
      debugPrint(
        'fetchBusinessId: Node API returned null business id — '
        'falling back to local caches',
      );
    } catch (e) {
      debugPrint('fetchBusinessId: Node API threw $e — falling back to local caches');
    }

    // ── Fallback 1: SessionService in-memory cache ─────────────────────────
    final fromSession = _sessionId();
    if (fromSession != null) {
      debugPrint('fetchBusinessId: resolved from SessionService → $fromSession');
      return fromSession;
    }

    // ── Fallback 2: SQLite local_businesses ────────────────────────────────
    final fromDb = await _localDbId();
    debugPrint('fetchBusinessId: resolved from SQLite → $fromDb');
    return fromDb;
  }

  /// Returns the businessId stored in the in-memory session, or null.
  String? _sessionId() => SessionService.instance.current?.businessId;

  /// Returns the first businessId found in the local SQLite businesses table.
  Future<String?> _localDbId() async {
    try {
      final db = await LocalDatabase.instance.database;
      final rows = await db.query(
        LocalDatabase.tableLocalBusinesses,
        columns: ['id'],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first['id'] as String?;
    } catch (e) {
      debugPrint('fetchBusinessId (_localDbId): SQLite error — $e');
    }
    return null;
  }

  // ── Fetch Paginated Guest Records for a Business ──────────────────────────

  Future<ApiResult<({List<GuestRecord> data, int totalCount, int pageCount})>> fetchGuestRecords(
    String businessId, {
    int page = 1,
    int pageSize = 10,
    String? status,
    String? checkInFrom,
    String? checkOutTo,
    String? purpose,
    String? transport,
  }) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      try {
        return await _fetchOnline(
          businessId,
          page: page,
          pageSize: pageSize,
          status: status,
          checkInFrom: checkInFrom,
          checkOutTo: checkOutTo,
          purpose: purpose,
          transport: transport,
        );
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          debugPrint('⚠️ fetchGuestRecords: Unauthorized (401). Falling back to local.');
          return _fetchOffline(
            businessId,
            page: page,
            pageSize: pageSize,
            status: status,
            checkInFrom: checkInFrom,
            checkOutTo: checkOutTo,
            purpose: purpose,
            transport: transport,
          );
        }
        return ApiResult.failure('Cloud error: ${e.message}');
      } catch (e) {
        debugPrint('⚠️ fetchGuestRecords: Online fetch failed ($e). Falling back to local.');
      }
    }
    return _fetchOffline(
      businessId,
      page: page,
      pageSize: pageSize,
      status: status,
      checkInFrom: checkInFrom,
      checkOutTo: checkOutTo,
      purpose: purpose,
      transport: transport,
    );
  }

  // ── Update a Record (stay info + lead guest + breakdowns) ────────────────

  Future<ApiResult<void>> updateRecord({
    required String recordId,
    required String checkIn,
    required String checkOut,
    required int totalGuests,
    List<String>? roomIds,
    required String purposeOfVisit,
    required String transportationMode,
    required List<GuestBreakdownEntry> breakdowns,
    String? leadCountry,
    String? leadMunicipality,
    String? leadProvince,
    String? leadNationality,
    String? leadPhilippinesRegion,
    bool leadIsOverseas = false,
    String? leadBirthdate,
    String? leadSex,
    String? actualCheckOut,
  }) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      try {
        return await _updateOnline(
          recordId:               recordId,
          checkIn:                checkIn,
          checkOut:               checkOut,
          totalGuests:            totalGuests,
          roomIds:                roomIds,
          purposeOfVisit:         purposeOfVisit,
          transportationMode:     transportationMode,
          breakdowns:             breakdowns,
          leadCountry:            leadCountry,
          leadMunicipality:       leadMunicipality,
          leadProvince:           leadProvince,
          leadNationality:        leadNationality,
          leadPhilippinesRegion:  leadPhilippinesRegion,
          leadIsOverseas:         leadIsOverseas,
          leadBirthdate:          leadBirthdate,
          leadSex:                leadSex,
          actualCheckOut:         actualCheckOut,
        );
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          return _updateOffline(
            recordId:               recordId,
            checkIn:                checkIn,
            checkOut:               checkOut,
            totalGuests:            totalGuests,
            roomIds:                roomIds,
            purposeOfVisit:         purposeOfVisit,
            transportationMode:     transportationMode,
            breakdowns:             breakdowns,
            leadCountry:            leadCountry,
            leadMunicipality:       leadMunicipality,
            leadProvince:           leadProvince,
            leadNationality:        leadNationality,
            leadPhilippinesRegion:  leadPhilippinesRegion,
            leadIsOverseas:         leadIsOverseas,
            leadBirthdate:          leadBirthdate,
            leadSex:                leadSex,
            actualCheckOut:         actualCheckOut,
          );
        }
        return ApiResult.failure('Update failed: ${e.message}');
      } catch (_) {}
    }
    
    return _updateOffline(
      recordId:               recordId,
      checkIn:                checkIn,
      checkOut:               checkOut,
      totalGuests:            totalGuests,
      roomIds:                roomIds,
      purposeOfVisit:         purposeOfVisit,
      transportationMode:     transportationMode,
      breakdowns:             breakdowns,
      leadCountry:            leadCountry,
      leadMunicipality:       leadMunicipality,
      leadProvince:           leadProvince,
      leadNationality:        leadNationality,
      leadPhilippinesRegion:  leadPhilippinesRegion,
      leadIsOverseas:         leadIsOverseas,
      leadBirthdate:          leadBirthdate,
      leadSex:                leadSex,
      actualCheckOut:         actualCheckOut,
    );
  }

  // ===========================================================================
  // ONLINE — fetch from Node API, then refresh local SQLite cache.
  // ===========================================================================

  Future<ApiResult<({List<GuestRecord> data, int totalCount, int pageCount})>> _fetchOnline(
    String businessId, {
    required int page,
    required int pageSize,
    String? status,
    String? checkInFrom,
    String? checkOutTo,
    String? purpose,
    String? transport,
  }) async {
    debugPrint('🔍 _fetchOnline: businessId=$businessId page=$page pageSize=$pageSize');

    final queryParams = <String, String>{
      'businessId': businessId,
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (status != null) queryParams['status'] = status;
    if (checkInFrom != null) queryParams['checkInFrom'] = checkInFrom;
    if (checkOutTo != null) queryParams['checkOutTo'] = checkOutTo;
    if (purpose != null && purpose != 'All') queryParams['purpose'] = purpose;
    if (transport != null && transport != 'All') queryParams['transport'] = transport;

    final uri = Uri.parse('/api/business/guest-records').replace(queryParameters: queryParams);
    final response = await get(uri.toString());

    Map<String, dynamic> body;
    List rows;
    int totalCount;
    int pageCount;
    try {
      body = handleResponse(response) as Map<String, dynamic>;
      rows = body['data'] as List? ?? [];
      totalCount = (body['totalCount'] as num?)?.toInt() ?? 0;
      pageCount = (body['pageCount'] as num?)?.toInt() ?? 0;
    } catch (e) {
      return ApiResult.failure('Failed to load records: $e');
    }

    debugPrint('☁️ _fetchOnline: found ${rows.length} cloud records (total=$totalCount, pages=$pageCount)');

    final cloudRecords = _parseNodeRows(rows);
    final allRecords   = List<GuestRecord>.from(cloudRecords);

    if (!kIsWeb) {
      final merged = await _getMergedLocalRecords(businessId, cloudRecords.map((r) => r.id).toSet());
      debugPrint('🧩 _fetchOnline: merged ${merged.length} local records');
      allRecords.addAll(merged);
      allRecords.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    }

    if (page == 1) {
      _refreshLocalCache(businessId, rows).catchError(
        (e) => debugPrint('⚠️ Local cache refresh error: $e'),
      );
    }

    return ApiResult.success((data: allRecords, totalCount: totalCount, pageCount: pageCount));
  }

  Future<List<GuestRecord>> _getMergedLocalRecords(String businessId, Set<String> cloudIds) async {
    try {
      final db = await LocalDatabase.instance.database;
      
      final now = DateTime.now().toUtc();
      final graceThreshold = now.subtract(const Duration(minutes: 2)).toIso8601String();

      final allLocalCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM ${LocalDatabase.tableGuestRecords}'));
      
      final rows = await db.query(
        LocalDatabase.tableGuestRecords,
        where: 'business_id = ? AND is_deleted = 0 AND (sync_status != ? OR local_updated_at > ?)',
        whereArgs: [businessId, LocalDatabase.syncSynced, graceThreshold],
      );
      
      if (rows.isEmpty && (allLocalCount ?? 0) > 0) {
        debugPrint('🔍 _getMergedLocalRecords: No matches found for biz $businessId, but DB has $allLocalCount total records.');
      }

      final records = <GuestRecord>[];

      for (final row in rows) {
        final recordId = row['id'] as String;
        if (cloudIds.contains(recordId)) continue;

        final checkIn  = row['check_in']  as String;
        final checkOut = row['check_out'] as String;

        final roomDetails = await _fetchLocalRoomDetails(db, recordId);
        final roomIds = roomDetails.map((r) => r.id).toList();

        records.add(GuestRecord(
          id:           recordId,
          checkIn:      checkIn,
          checkOut:     checkOut,
          actualCheckOut: row['actual_checkout'] as String?,
          nights:       _calcNights(checkIn, checkOut),
          guests:       (row['total_guests']       as int?) ?? 0,
          rooms:        roomDetails.length,
          roomDetails:  roomDetails,
          roomIds:      roomIds,
          purpose:      row['purpose_of_visit']     as String? ?? '',
          transport:    row['transportation_mode']  as String? ?? '',
          status:       (row['status'] as String?) == 'archived'
              ? GuestRecordStatus.archived
              : GuestRecordStatus.active,
          demographics: _buildDemographicsFromLeadFields(row),
          createdAt:    row['created_at'] as String?,
          leadCountry:            row['lead_country'] as String?,
          leadMunicipality:       row['lead_city_municipality'] as String?,
          leadProvince:           row['lead_province'] as String?,
          leadNationality:        row['lead_nationality'] as String?,
          leadPhilippinesRegion:  row['lead_philippines_region'] as String?,
          leadIsOverseas:         (row['lead_is_overseas'] as int?) == 1,
          leadBirthdate:          row['lead_birthdate'] as String?,
          leadSex:                _normaliseSex(row['lead_sex'] as String?),
        ));
      }
      return records;
    } catch (e) {
      debugPrint('⚠️ _getMergedLocalRecords error: $e');
      return [];
    }
  }

  // ===========================================================================
  // OFFLINE — read entirely from SQLite.
  // ===========================================================================

  Future<ApiResult<({List<GuestRecord> data, int totalCount, int pageCount})>> _fetchOffline(
    String businessId, {
    required int page,
    required int pageSize,
    String? status,
    String? checkInFrom,
    String? checkOutTo,
    String? purpose,
    String? transport,
  }) async {
    try {
      final db = await LocalDatabase.instance.database;

      // ── Build WHERE clause ──────────────────────────────────────────────
      final conditions = ['business_id = ?', 'is_deleted = 0'];
      final args = <dynamic>[businessId];

      if (status == 'archived') {
        conditions.add("status = 'archived'");
      } else {
        conditions.add("status = 'active'");
      }

      if (checkInFrom != null) {
        conditions.add('check_in >= ?');
        args.add(checkInFrom);
      }
      if (checkOutTo != null) {
        conditions.add('check_out <= ?');
        args.add(checkOutTo);
      }
      if (purpose != null && purpose != 'All') {
        conditions.add('purpose_of_visit = ?');
        args.add(purpose);
      }
      if (transport != null && transport != 'All') {
        conditions.add('transportation_mode = ?');
        args.add(transport);
      }

      final whereClause = conditions.join(' AND ');

      // ── Count total ─────────────────────────────────────────────────────
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ${LocalDatabase.tableGuestRecords} WHERE $whereClause',
        args,
      );
      final totalCount = (countResult.first['cnt'] as int?) ?? 0;

      if (totalCount == 0) {
        return ApiResult.success((data: [], totalCount: 0, pageCount: 0));
      }

      final pageCount = (totalCount / pageSize).ceil();

      // ── Fetch paginated rows ────────────────────────────────────────────
      final offset = (page - 1) * pageSize;
      final rows = await db.query(
        LocalDatabase.tableGuestRecords,
        where:   whereClause,
        whereArgs: args,
        orderBy: 'created_at DESC',
        limit:   pageSize,
        offset:  offset,
      );

      final records = <GuestRecord>[];

      for (final row in rows) {
        final recordId = row['id'] as String;

        final checkIn  = row['check_in']  as String;
        final checkOut = row['check_out'] as String;

        final roomDetails = await _fetchLocalRoomDetails(db, recordId);
        final roomIds = roomDetails.map((r) => r.id).toList();

        records.add(GuestRecord(
          id:           recordId,
          checkIn:      checkIn,
          checkOut:     checkOut,
          actualCheckOut: row['actual_checkout'] as String?,
          nights:       _calcNights(checkIn, checkOut),
          guests:       (row['total_guests']       as int?) ?? 0,
          rooms:        roomDetails.length,
          roomDetails:  roomDetails,
          roomIds:      roomIds,
          purpose:      row['purpose_of_visit']     as String? ?? '',
          transport:    row['transportation_mode']  as String? ?? '',
          status:       (row['status'] as String?) == 'archived'
              ? GuestRecordStatus.archived
              : GuestRecordStatus.active,
          demographics: _buildDemographicsFromLeadFields(row),
          createdAt:    row['created_at'] as String?,
          leadCountry:            row['lead_country'] as String?,
          leadMunicipality:       row['lead_city_municipality'] as String?,
          leadProvince:           row['lead_province'] as String?,
          leadNationality:        row['lead_nationality'] as String?,
          leadPhilippinesRegion:  row['lead_philippines_region'] as String?,
          leadIsOverseas:         (row['lead_is_overseas'] as int?) == 1,
          leadBirthdate:          row['lead_birthdate'] as String?,
          leadSex:                _normaliseSex(row['lead_sex'] as String?),
        ));
      }

      return ApiResult.success((data: records, totalCount: totalCount, pageCount: pageCount));
    } catch (e) {
      debugPrint('❌ fetchGuestRecords (offline) error: $e');
      return ApiResult.failure('Failed to load local records.');
    }
  }

  // ===========================================================================
  // ONLINE UPDATE — Node API first, then mirror to SQLite as synced.
  // ===========================================================================

  Future<ApiResult<void>> _updateOnline({
    required String recordId,
    required String checkIn,
    required String checkOut,
    required int totalGuests,
    List<String>? roomIds,
    required String purposeOfVisit,
    required String transportationMode,
    required List<GuestBreakdownEntry> breakdowns,
    String? leadCountry,
    String? leadMunicipality,
    String? leadProvince,
    String? leadNationality,
    String? leadPhilippinesRegion,
    bool leadIsOverseas = false,
    String? leadBirthdate,
    String? leadSex,
    String? actualCheckOut,
  }) async {
    try {
      final businessId = SessionService.instance.current?.businessId;
      final payload = <String, dynamic>{
        'businessId':            businessId,
        'checkIn':               checkIn,
        'checkOut':              checkOut,
        'actualCheckOut':        actualCheckOut,
        'totalGuests':           totalGuests,
        'purposeOfVisit':        purposeOfVisit,
        'transportationMode':    transportationMode,
        'leadCountry':           leadCountry,
        'leadMunicipality':      leadMunicipality,
        'leadProvince':          leadProvince,
        'leadNationality':       leadNationality,
        'leadPhilippinesRegion': leadPhilippinesRegion,
        'leadIsOverseas':        leadIsOverseas,
        'leadSex':               leadSex?.toLowerCase(),
        'leadBirthdate':         leadBirthdate,
        'breakdowns':            breakdowns.map((b) => _breakdownEntryToPayload(b)).toList(),
      };
      if (roomIds != null) {
        payload['roomIds'] = roomIds;
      }

      await put('/api/business/guest-records/$recordId', payload);

      if (!kIsWeb) {
        final db = await LocalDatabase.instance.database;

        // If the record was originally pending_create (e.g. POST failed),
        // keep it that way so the create is pushed on the next sync cycle
        // with proper room associations. Marking it synced here would skip
        // the create and leave the backend without junction rows.
        final currentState = await db.query(
          LocalDatabase.tableGuestRecords,
          columns: ['sync_status'],
          where: 'id = ?',
          whereArgs: [recordId],
          limit: 1,
        );
        final preserveCreate = currentState.isNotEmpty &&
            currentState.first['sync_status'] == LocalDatabase.syncPendingCreate;

        await db.update(
          LocalDatabase.tableGuestRecords,
          {
            'check_in':                checkIn,
            'check_out':               checkOut,
            'actual_checkout':         actualCheckOut,
            'total_guests':            totalGuests,
            'purpose_of_visit':        purposeOfVisit,
            'transportation_mode':     transportationMode,
            'lead_country':            leadCountry,
            'lead_city_municipality':  leadMunicipality,
            'lead_province':           leadProvince,
            'lead_nationality':        leadNationality,
            'lead_philippines_region': leadPhilippinesRegion,
            'lead_is_overseas':        leadIsOverseas ? 1 : 0,
            'lead_birthdate':          leadBirthdate,
            'lead_sex':                leadSex?.toLowerCase(),
            'updated_at':              DateTime.now().toUtc().toIso8601String(),
            'sync_status':             preserveCreate
                ? LocalDatabase.syncPendingCreate
                : LocalDatabase.syncSynced,
            'local_updated_at':        DateTime.now().toUtc().toIso8601String(),
          },
          where:     'id = ?',
          whereArgs: [recordId],
        );
        // Update room assignments (skip for post-checkout — rooms are locked)
        if (roomIds != null && actualCheckOut == null) {
          await _updateLocalRoomAssignments(db, recordId, businessId ?? '', roomIds);
        }
      }

      return const ApiResult.success(null);
    } catch (e) {
      return ApiResult.failure('Failed to update record: $e');
    }
  }

  // ===========================================================================
  // OFFLINE UPDATE — SQLite only, tagged pending_update.
  // ===========================================================================

  Future<ApiResult<void>> _updateOffline({
    required String recordId,
    required String checkIn,
    required String checkOut,
    required int totalGuests,
    List<String>? roomIds,
    required String purposeOfVisit,
    required String transportationMode,
    required List<GuestBreakdownEntry> breakdowns,
    String? leadCountry,
    String? leadMunicipality,
    String? leadProvince,
    String? leadNationality,
    String? leadPhilippinesRegion,
    bool leadIsOverseas = false,
    String? leadBirthdate,
    String? leadSex,
    String? actualCheckOut,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final db  = await LocalDatabase.instance.database;

      // Preserve pending_create so the initial POST (with room associations)
      // is pushed first. Overwriting to pending_update would skip the create
      // and the subsequent PUT checkout would upsert the record without
      // junction rows, losing room data.
      final currentState = await db.query(
        LocalDatabase.tableGuestRecords,
        columns: ['sync_status'],
        where: 'id = ?',
        whereArgs: [recordId],
        limit: 1,
      );
      final preserveCreate = currentState.isNotEmpty &&
          currentState.first['sync_status'] == LocalDatabase.syncPendingCreate;

      await db.update(
        LocalDatabase.tableGuestRecords,
        {
          'check_in':                checkIn,
          'check_out':               checkOut,
          'actual_checkout':         actualCheckOut,
          'total_guests':            totalGuests,
          'purpose_of_visit':        purposeOfVisit,
          'transportation_mode':     transportationMode,
          'lead_country':            leadCountry,
          'lead_city_municipality':  leadMunicipality,
          'lead_province':           leadProvince,
          'lead_nationality':        leadNationality,
          'lead_philippines_region': leadPhilippinesRegion,
          'lead_is_overseas':        leadIsOverseas ? 1 : 0,
          'lead_birthdate':          leadBirthdate,
          'lead_sex':                leadSex?.toLowerCase(),
          'updated_at':              now,
          'sync_status':             preserveCreate
              ? LocalDatabase.syncPendingCreate
              : LocalDatabase.syncPendingUpdate,
          'local_updated_at':        now,
        },
        where:     'id = ?',
        whereArgs: [recordId],
      );

      // Update room assignments locally (skip for post-checkout — rooms are locked)
      if (roomIds != null && actualCheckOut == null) {
        final businessId = SessionService.instance.current?.businessId ?? '';
        await _updateLocalRoomAssignments(db, recordId, businessId, roomIds);
      }

      return const ApiResult.success(null);
    } catch (e) {
      debugPrint('❌ updateRecord (offline) error: $e');
      return ApiResult.failure(
        'Failed to save changes locally. Please try again.',
      );
    }
  }

  // ===========================================================================
  // Local cache helpers
  // ===========================================================================

  /// Fetches room details for a guest record from the local SQLite
  /// junction table `local_guest_record_rooms` joined with `local_rooms`.
  Future<List<GuestRoom>> _fetchLocalRoomDetails(dynamic db, String recordId) async {
    try {
      final rows = await db.rawQuery(
        'SELECT r.id, r.room_number, r.capacity, r.room_status '
        'FROM local_guest_record_rooms grr '
        'JOIN local_rooms r ON r.id = grr.room_id '
        'WHERE grr.guest_record_id = ?',
        [recordId],
      ) as List<Map<String, Object?>>;
      return rows.map((r) => GuestRoom(
        id: r['id'] as String? ?? '',
        roomNumber: r['room_number'] as String? ?? '',
        capacity: (r['capacity'] as int?) ?? 0,
        status: r['room_status'] as String? ?? 'vacant',
      )).toList();
    } catch (e) {
      debugPrint('⚠️ _fetchLocalRoomDetails error: $e');
      return [];
    }
  }

  Future<void> _refreshLocalCache(String businessId, List rows) async {
    if (kIsWeb) {
      debugPrint('⏭ _refreshLocalCache: skipped on web — local SQLite is disabled');
      return;
    }

    final db = await LocalDatabase.instance.database;

    // Insert / Update from Cloud
    for (final row in rows) {
      final recordId = row['id'] as String;

      final pending = await db.query(
        LocalDatabase.tableGuestRecords,
        columns:   ['sync_status'],
        where:     'id = ? AND sync_status != ?',
        whereArgs: [recordId, LocalDatabase.syncSynced],
        limit:     1,
      );
      if (pending.isNotEmpty) continue;

      await db.insert(
        LocalDatabase.tableGuestRecords,
        {
          'id':                      recordId,
          'business_id':             businessId,
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
          'is_deleted':              0,
          'created_at':              row['created_at'],
          'updated_at':              row['updated_at'],
          'sync_status':             LocalDatabase.syncSynced,
          'local_updated_at':        null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Cache junction table + room data from cloud response
      final roomsList = (row['rooms'] as List?) ?? [];
      if (roomsList.isNotEmpty) {
        // Clear old junction rows for this record
        await db.delete(
          LocalDatabase.tableGuestRecordRooms,
          where: 'guest_record_id = ?',
          whereArgs: [recordId],
        );
        for (final room in roomsList) {
          final roomId = room['id'] as String?;
          if (roomId == null || roomId.isEmpty) continue;
          // Ensure room exists in local_rooms (FK requirement)
          // INSERT OR IGNORE: if the room already exists (e.g. from
          // _pullRoomsFromBackend), its real data is preserved.
          await db.rawInsert(
            'INSERT OR IGNORE INTO ${LocalDatabase.tableLocalRooms} '
            '(id, business_id, room_number, capacity, room_status, sync_status, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            [
              roomId,
              businessId,
              room['roomNumber'] ?? '',
              room['capacity'] ?? 1,
              'vacant',
              LocalDatabase.syncSynced,
              room['created_at'] ?? room['createdAt'],
              room['updated_at'] ?? room['updatedAt'],
            ],
          );
          // Insert junction row
          final junctionId = '$recordId-$roomId';
          await db.insert(
            LocalDatabase.tableGuestRecordRooms,
            {
              'id':               junctionId,
              'guest_record_id':  recordId,
              'room_id':          roomId,
              'status':           room['status'] ?? 'active',
              'created_at':       room['created_at'] ?? room['createdAt'],
              'updated_at':       room['updated_at'] ?? room['updatedAt'],
              'sync_status':      LocalDatabase.syncSynced,
              'local_updated_at': null,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    }
  }

  /// Updates the lead guest fields on a local_guest_records row from a
  /// GuestBreakdownEntry list. Uses the first entry as the lead guest.
  Future<void> _updateLeadFields(
    dynamic db,
    String recordId,
    List<GuestBreakdownEntry> breakdowns,
  ) async {
    if (breakdowns.isEmpty) return;

    final b             = breakdowns.first;
    final isOverseas    = b.isOverseas;
    final isPhilippines = !isOverseas && b.country == 'Philippines';

    await db.update(
      LocalDatabase.tableGuestRecords,
      {
        'lead_country':            isOverseas ? null : b.country,
        'lead_nationality':        isPhilippines ? b.nationality : null,
        'lead_philippines_region': isPhilippines ? b.philippinesRegion : null,
        'lead_province':           isOverseas ? null : b.province,
        'lead_city_municipality':  isOverseas ? null : b.municipalityCity,
        'lead_is_overseas':        isOverseas ? 1 : 0,
        'lead_sex':                _mapSex(b.sex),
      },
      where:     'id = ?',
      whereArgs: [recordId],
    );
  }

  /// Updates room assignments in the local junction table.
  Future<void> _updateLocalRoomAssignments(
    dynamic db,
    String recordId,
    String businessId,
    List<String> roomIds,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final isOnline = ConnectivityService.instance.isOnline && hasToken;
    final junctionSyncStatus = isOnline
        ? LocalDatabase.syncSynced
        : LocalDatabase.syncPendingUpdate;

    // Capture old room IDs before clearing so we can diff later
    final oldRoomIds = <String>[];
    final oldRows = await db.query(
      LocalDatabase.tableGuestRecordRooms,
      columns: ['room_id'],
      where: 'guest_record_id = ?',
      whereArgs: [recordId],
    );
    for (final row in oldRows) {
      oldRoomIds.add(row['room_id'] as String);
    }

    // Clear old links
    await db.delete(
      LocalDatabase.tableGuestRecordRooms,
      where: 'guest_record_id = ?',
      whereArgs: [recordId],
    );
    // Ensure each room exists in local_rooms (FK constraint requires it)
    // INSERT OR IGNORE preserves real room data if the room already exists locally.
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
          now,
          now,
        ],
      );
    }
    // Insert new links
    for (final roomId in roomIds) {
      final junctionId = DateTime.now().toUtc().toIso8601String() + '-' + roomId;
      await db.insert(
        LocalDatabase.tableGuestRecordRooms,
        {
          'id':               junctionId,
          'guest_record_id':  recordId,
          'room_id':          roomId,
          'status':           'active',
          'created_at':       now,
          'updated_at':       now,
          'sync_status':      junctionSyncStatus,
          'local_updated_at': isOnline ? null : now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // Mark newly assigned rooms as occupied locally
    final roomSyncStatus = isOnline
        ? LocalDatabase.syncSynced
        : LocalDatabase.syncPendingUpdate;
    for (final roomId in roomIds) {
      await db.update(
        LocalDatabase.tableLocalRooms,
        {
          'room_status':      'occupied',
          'sync_status':      roomSyncStatus,
          'local_updated_at': now,
        },
        where:     'id = ? AND room_status != ?',
        whereArgs: [roomId, 'occupied'],
      );
    }

    // Free rooms no longer referenced by any active guest record
    final removedRoomIds = oldRoomIds.where((id) => !roomIds.contains(id));
    for (final roomId in removedRoomIds) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ${LocalDatabase.tableGuestRecordRooms} grr '
        'JOIN ${LocalDatabase.tableGuestRecords} gr ON gr.id = grr.guest_record_id '
        'WHERE grr.room_id = ? AND grr.guest_record_id != ? '
        'AND gr.status = ? AND gr.is_deleted = 0',
        [roomId, recordId, 'active'],
      );
      final refCount = (result.first['cnt'] as int?) ?? 0;
      if (refCount == 0) {
        await db.update(
          LocalDatabase.tableLocalRooms,
          {
            'room_status':      'vacant',
            'sync_status':      roomSyncStatus,
            'local_updated_at': now,
          },
          where:     'id = ?',
          whereArgs: [roomId],
        );
      }
    }
  }

  // ===========================================================================
  // Payload Mappers
  // ===========================================================================

  Map<String, dynamic> _breakdownEntryToPayload(GuestBreakdownEntry b) {
    final isOverseas    = b.isOverseas;
    final isPhilippines = !isOverseas && b.country == 'Philippines';
    return {
      'isOverseas':        isOverseas,
      'country':            isOverseas ? null : b.country,
      'nationality':        isPhilippines ? b.nationality : null,
      'philippinesRegion': isPhilippines ? b.philippinesRegion : null,
      'province':          isOverseas ? null : b.province,
      'municipalityCity':  isOverseas ? null : b.municipalityCity,
      'sex':                _mapSex(b.sex),
      'ageGroup':          _mapAgeGroup(b.ageGroup),
      'count':              b.count,
    };
  }

  // ===========================================================================
  // Parsing helpers
  // ===========================================================================

  List<GuestRecord> _parseNodeRows(List rows) {
    return rows.map((row) {
      final breakdowns = (row['guest_breakdowns'] as List?) ?? [];
      final checkIn    = row['check_in']  as String;
      final checkOut   = row['check_out'] as String;
      final statusStr  = row['status']    as String? ?? 'active';

      final roomsList = (row['rooms'] as List?) ?? [];
      final roomDetails = roomsList.map((r) => GuestRoom(
        id: r['id'] as String? ?? '',
        roomNumber: r['roomNumber'] as String? ?? '',
        capacity: (r['capacity'] as int?) ?? 0,
        status: r['status'] as String? ?? 'active',
      )).toList();
      final roomIds = roomsList.map((r) => r['id'] as String? ?? '').where((id) => id.isNotEmpty).toList();

      return GuestRecord(
        id:           row['id'] as String,
        checkIn:      checkIn,
        checkOut:     checkOut,
        actualCheckOut: row['actual_check_out'] as String?,
        nights:       _calcNights(checkIn, checkOut),
        guests:       (row['total_guests']       as int?) ?? 0,
        rooms:        roomsList.length,
        roomDetails:  roomDetails,
        roomIds:      roomIds,
        purpose:      row['purpose_of_visit']     as String? ?? '',
        transport:    row['transportation_mode']  as String? ?? '',
        status:       statusStr == 'archived'
            ? GuestRecordStatus.archived
            : GuestRecordStatus.active,
        demographics: breakdowns.isNotEmpty
            ? _buildDemographicsFromNode(breakdowns)
            : _buildDemographicsFromLeadFields(row),
        createdAt:    row['created_at'] as String?,
        leadCountry:            row['lead_country'] as String?,
        leadMunicipality:       row['lead_city_municipality'] as String?,
        leadProvince:           row['lead_province'] as String?,
        leadNationality:        row['lead_nationality'] as String?,
        leadPhilippinesRegion:  row['lead_philippines_region'] as String?,
        leadIsOverseas:         (row['lead_is_overseas'] == true || row['lead_is_overseas'] == 1),
        leadBirthdate:          row['lead_birthdate'] as String?,
        leadSex:                _normaliseSex(row['lead_sex'] as String?),
      );
    }).toList();
  }

  GuestDemographics? _buildDemographicsFromNode(List breakdowns) {
    if (breakdowns.isEmpty) return null;

    final ageGroups = <String, int>{};
    final sex       = <String, int>{};
    final countries = <String, int>{};
    final entries   = <GuestBreakdownEntry>[];

    for (final b in breakdowns) {
      final count      = (b['count']       as int?)  ?? 0;
      final isOverseas = (b['is_overseas'] == true || b['is_overseas'] == 1);
      final ageGroup   = b['age_group']    as String? ?? 'Unknown';
      final s          = b['sex']          as String? ?? 'Unknown';

      ageGroups[ageGroup] = (ageGroups[ageGroup] ?? 0) + count;
      sex[s]              = (sex[s]              ?? 0) + count;

      final String countryKey;
      if (isOverseas) {
        countryKey = 'Overseas';
      } else {
        final country = b['country'] as String? ?? 'Unknown';
        final region  = b['philippines_region'] as String?;
        countryKey    = (country == 'Philippines' &&
                region != null && region != 'N/A')
            ? 'PH – $region'
            : country;
      }
      countries[countryKey] = (countries[countryKey] ?? 0) + count;

      entries.add(GuestBreakdownEntry(
        country:           isOverseas ? null : b['country'] as String?,
        nationality:       (!isOverseas && b['country'] == 'Philippines')
            ? b['nationality'] as String?
            : null,
        philippinesRegion: (!isOverseas &&
                b['country'] == 'Philippines' &&
                (b['philippines_region'] as String?) != null &&
                (b['philippines_region'] as String?) != 'N/A')
            ? b['philippines_region'] as String?
            : null,
        province:          (!isOverseas ? b['province'] as String? : null),
        municipalityCity:  (!isOverseas ? b['municipality_city'] as String? : null),
        sex:        b['sex']       as String? ?? '',
        ageGroup:   b['age_group'] as String? ?? '',
        count:      count,
        isOverseas: isOverseas,
      ));
    }

    return GuestDemographics(
      ageGroups:       ageGroups,
      sexDistribution: sex,
      countries:       countries,
      breakdowns:      entries,
    );
  }

  GuestDemographics? _buildDemographicsFromLocal(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return null;

    final ageGroups = <String, int>{};
    final sex       = <String, int>{};
    final countries = <String, int>{};
    final entries   = <GuestBreakdownEntry>[];

    for (final b in rows) {
      final count      = (b['count']       as int?) ?? 0;
      final isOverseas = (b['is_overseas'] as int?) == 1;
      final ageGroup   = b['age_group']    as String? ?? 'Unknown';
      final s          = b['sex']          as String? ?? 'Unknown';

      ageGroups[ageGroup] = (ageGroups[ageGroup] ?? 0) + count;
      sex[s]              = (sex[s]              ?? 0) + count;

      final String countryKey;
      if (isOverseas) {
        countryKey = 'Overseas';
      } else {
        final country = b['country'] as String? ?? 'Unknown';
        final region  = b['philippines_region'] as String?;
        countryKey    = (country == 'Philippines' &&
                region != null && region != 'N/A')
            ? 'PH – $region'
            : country;
      }
      countries[countryKey] = (countries[countryKey] ?? 0) + count;

      entries.add(GuestBreakdownEntry(
        country:           isOverseas ? null : b['country'] as String?,
        nationality:       (!isOverseas && b['country'] == 'Philippines')
            ? b['nationality'] as String?
            : null,
        philippinesRegion: (!isOverseas &&
                b['country'] == 'Philippines' &&
                (b['philippines_region'] as String?) != null &&
                (b['philippines_region'] as String?) != 'N/A')
            ? b['philippines_region'] as String?
            : null,
        province:          (!isOverseas ? b['province'] as String? : null),
        municipalityCity:  (!isOverseas ? b['municipality_city'] as String? : null),
        sex:        b['sex']       as String? ?? '',
        ageGroup:   b['age_group'] as String? ?? '',
        count:      count,
        isOverseas: isOverseas,
      ));
    }

    return GuestDemographics(
      ageGroups:       ageGroups,
      sexDistribution: sex,
      countries:       countries,
      breakdowns:      entries,
    );
  }

  /// Builds GuestDemographics from the lead guest fields stored directly on a
  /// local_guest_records row (the breakdowns table was retired in v2).
  GuestDemographics? _buildDemographicsFromLeadFields(
    Map<String, dynamic> row,
  ) {
    final s = row['lead_sex'] as String?;
    if (s == null || s.isEmpty) return null;

    final sex = <String, int>{s: 1};

    final isOverseas = (row['lead_is_overseas'] as int?) == 1;
    final country    = row['lead_country'] as String?;
    final region     = row['lead_philippines_region'] as String?;

    final countries = <String, int>{};
    final String countryKey;
    if (isOverseas) {
      countryKey = 'Overseas';
    } else if (country == 'Philippines' && region != null && region != 'N/A') {
      countryKey = 'PH – $region';
    } else {
      countryKey = country ?? 'Unknown';
    }
    countries[countryKey] = 1;

    // Compute age group from lead_birthdate + check_in.
    String ageGroup = 'Unknown';
    final birthdateStr = row['lead_birthdate'] as String?;
    final checkInStr   = row['check_in'] as String?;
    if (birthdateStr != null && checkInStr != null) {
      final birthdate = DateTime.tryParse(birthdateStr);
      final checkIn   = DateTime.tryParse(checkInStr);
      if (birthdate != null && checkIn != null) {
        int age = checkIn.year - birthdate.year;
        if (checkIn.month < birthdate.month ||
            (checkIn.month == birthdate.month && checkIn.day < birthdate.day)) {
          age--;
        }
        if (age <= 9)       ageGroup = '0-9';
        else if (age <= 17) ageGroup = '10-17';
        else if (age <= 25) ageGroup = '18-25';
        else if (age <= 35) ageGroup = '26-35';
        else if (age <= 45) ageGroup = '36-45';
        else if (age <= 55) ageGroup = '46-55';
        else                ageGroup = '56+';
      }
    }

    final ageGroups = <String, int>{ageGroup: 1};

    final entries = <GuestBreakdownEntry>[
      GuestBreakdownEntry(
        country:           isOverseas ? null : country,
        nationality:       (!isOverseas && country == 'Philippines')
            ? row['lead_nationality'] as String?
            : null,
        philippinesRegion: (!isOverseas &&
                country == 'Philippines' &&
                region != null &&
                region != 'N/A')
            ? region
            : null,
        province:          (!isOverseas ? row['lead_province'] as String? : null),
        municipalityCity:  (!isOverseas ? row['lead_city_municipality'] as String? : null),
        sex:        s,
        ageGroup:   ageGroup,
        count:      1,
        isOverseas: isOverseas,
      ),
    ];

    return GuestDemographics(
      ageGroups:       ageGroups,
      sexDistribution: sex,
      countries:       countries,
      breakdowns:      entries,
    );
  }

  // ===========================================================================
  // Value mappers
  // ===========================================================================

  String _calcNights(String checkIn, String checkOut) {
    try {
      final inDate  = DateTime.parse(checkIn);
      final outDate = DateTime.parse(checkOut);
      final n       = outDate.difference(inDate).inDays;
      return '$n night${n == 1 ? '' : 's'}';
    } catch (_) {
      return '—';
    }
  }

  String _mapSex(String sex) {
    switch (sex.toLowerCase()) {
      case 'male':   return 'male';
      case 'female': return 'female';
      default:       return 'male';
    }
  }

  /// Normalise sex value from DB to Title Case for UI dropdowns.
  static String _normaliseSex(String? sex) {
    if (sex == null || sex.isEmpty) return sex ?? '';
    return sex[0].toUpperCase() + sex.substring(1).toLowerCase();
  }

  String _mapAgeGroup(String ageGroup) {
    final normalised = ageGroup.trim().replaceAll('–', '-');
    switch (normalised) {
      case '0-9':
      case '1-9':               return '0-9';
      case '10-17':             return '10-17';
      case '18-25':             return '18-25';
      case '26-35':             return '26-35';
      case '36-45':             return '36-45';
      case '46-55':             return '46-55';
      case '56+':               return '56+';
      case 'prefer_not_to_say':
      case 'prefer not to say': return 'prefer_not_to_say';
      default:                  return 'prefer_not_to_say';
    }
  }
}