import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'base_api.dart';

// ─── Room CRUD API ──────────────────────────────────────────────────────────

class BusinessRoomApi extends BaseApi {
  // ── Fetch Business ID ─────────────────────────────────────────────────────

  Future<String?> fetchBusinessId() async {
    if (!ConnectivityService.instance.isOnline) {
      return _sessionId() ?? await _localDbId();
    }

    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      final id = data?['business']?['id']?.toString();
      if (id != null) return id;
    } catch (_) {}

    return _sessionId() ?? await _localDbId();
  }

  String? _sessionId() => SessionService.instance.current?.businessId;

  Future<String?> _localDbId() async {
    try {
      final db = await LocalDatabase.instance.database;
      final rows = await db.query(
        LocalDatabase.tableLocalBusinesses,
        columns: ['id'],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first['id'] as String?;
    } catch (_) {}
    return null;
  }

  // ── Fetch ALL rooms for a business ────────────────────────────────────────

  Future<List<RoomData>> fetchRooms(String businessId) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      try {
        return await _fetchRoomsOnline(businessId);
      } catch (e) {
        debugPrint('⚠️ fetchRooms: online failed ($e), falling back to local');
      }
    }
    return _fetchRoomsLocal(businessId);
  }

  Future<List<RoomData>> _fetchRoomsOnline(String businessId) async {
    final response = await get('/api/business/rooms?businessId=$businessId&fetchAll=true');
    final body = handleResponse(response) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? [];

    final rooms = data.map((r) => RoomData(
      id: r['id'] as String,
      roomNumber: r['roomNumber'] as String,
      capacity: r['capacity'] as int,
      roomStatus: r['roomStatus'] as String? ?? 'vacant',
    )).toList();

    // Cache locally
    if (!kIsWeb) {
      await _cacheRoomsLocally(businessId, rooms);
    }

    return rooms;
  }

  Future<List<RoomData>> _fetchRoomsLocal(String businessId) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      LocalDatabase.tableLocalRooms,
      where: 'business_id = ?',
      whereArgs: [businessId],
      orderBy: 'room_number',
    );
    return rows.map((r) => RoomData(
      id: r['id'] as String,
      roomNumber: r['room_number'] as String,
      capacity: r['capacity'] as int,
      roomStatus: r['room_status'] as String? ?? 'vacant',
      createdAt: r['created_at'] as String?,
      updatedAt: r['updated_at'] as String?,
    )).toList();
  }

  // ── Fetch Paginated Rooms ─────────────────────────────────────────────────

  Future<RoomsApiResult<RoomsPaginatedData>> fetchRoomsPaginated(
    String businessId, {
    int page = 1,
    int pageSize = 10,
    String? status,
    String? search,
  }) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      try {
        return await _fetchRoomsPaginatedOnline(
          businessId,
          page: page,
          pageSize: pageSize,
          status: status,
          search: search,
        );
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          return _fetchRoomsPaginatedOffline(
            businessId,
            page: page,
            pageSize: pageSize,
            status: status,
            search: search,
          );
        }
        return RoomsApiResult.failure('Cloud error: ${e.message}');
      } catch (e) {
        debugPrint('⚠️ fetchRoomsPaginated: online failed ($e), falling back to local');
      }
    }
    return _fetchRoomsPaginatedOffline(
      businessId,
      page: page,
      pageSize: pageSize,
      status: status,
      search: search,
    );
  }

  Future<RoomsApiResult<RoomsPaginatedData>> _fetchRoomsPaginatedOnline(
    String businessId, {
    int page = 1,
    int pageSize = 10,
    String? status,
    String? search,
  }) async {
    final params = <String>[
      'businessId=$businessId',
      'page=$page',
      'pageSize=$pageSize',
    ];
    if (status != null && status != 'All') params.add('status=$status');
    if (search != null && search.isNotEmpty) params.add('search=$search');

    final response = await get('/api/business/rooms?${params.join('&')}');
    final body = handleResponse(response) as Map<String, dynamic>;

    final data = (body['data'] as List<dynamic>? ?? []).map((r) => RoomData(
      id: r['id'] as String,
      roomNumber: r['roomNumber'] as String,
      capacity: r['capacity'] as int,
      roomStatus: r['roomStatus'] as String? ?? 'vacant',
      createdAt: r['createdAt'] as String?,
      updatedAt: r['updatedAt'] as String?,
    )).toList();

    final totalCount = body['totalCount'] as int? ?? 0;
    final pageCount = body['pageCount'] as int? ?? 0;

    return RoomsApiResult.success(RoomsPaginatedData(
      data: data,
      totalCount: totalCount,
      pageCount: pageCount,
    ));
  }

  Future<RoomsApiResult<RoomsPaginatedData>> _fetchRoomsPaginatedOffline(
    String businessId, {
    int page = 1,
    int pageSize = 10,
    String? status,
    String? search,
  }) async {
    try {
      final db = await LocalDatabase.instance.database;
      final conditions = <String>['business_id = ?'];
      final whereArgs = <dynamic>[businessId];

      if (status != null && status != 'All') {
        conditions.add('room_status = ?');
        whereArgs.add(status);
      }
      if (search != null && search.isNotEmpty) {
        conditions.add('room_number LIKE ?');
        whereArgs.add('%$search%');
      }

      final whereClause = conditions.join(' AND ');
      final countResult = await db.query(
        LocalDatabase.tableLocalRooms,
        columns: ['COUNT(*) as total'],
        where: whereClause,
        whereArgs: whereArgs,
      );
      final totalCount = countResult.first['total'] as int? ?? 0;
      final pageCount = (totalCount / pageSize).ceil();

      if (totalCount == 0) {
        return RoomsApiResult.success(const RoomsPaginatedData(
          data: [],
          totalCount: 0,
          pageCount: 0,
        ));
      }

      final offset = (page - 1) * pageSize;
      final rows = await db.query(
        LocalDatabase.tableLocalRooms,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'room_number',
        limit: pageSize,
        offset: offset,
      );

      final data = rows.map((r) => RoomData(
        id: r['id'] as String,
        roomNumber: r['room_number'] as String,
        capacity: r['capacity'] as int,
        roomStatus: r['room_status'] as String? ?? 'vacant',
        createdAt: r['created_at'] as String?,
        updatedAt: r['updated_at'] as String?,
      )).toList();

      return RoomsApiResult.success(RoomsPaginatedData(
        data: data,
        totalCount: totalCount,
        pageCount: pageCount,
      ));
    } catch (e) {
      debugPrint('❌ _fetchRoomsPaginatedOffline: $e');
      return RoomsApiResult.failure('Failed to load rooms locally.');
    }
  }

  Future<void> _cacheRoomsLocally(String businessId, List<RoomData> rooms) async {
    if (kIsWeb) return;
    try {
      final db = await LocalDatabase.instance.database;
      for (final room in rooms) {
        // Skip rooms that have local pending changes (user edited them offline)
        final existing = await db.query(
          LocalDatabase.tableLocalRooms,
          columns: ['sync_status'],
          where: 'id = ?',
          whereArgs: [room.id],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final localSync = existing.first['sync_status'] as String?;
          if (localSync != null && localSync != LocalDatabase.syncSynced) {
            continue;
          }
        }

        await db.insert(
          LocalDatabase.tableLocalRooms,
          {
            'id':               room.id,
            'business_id':      businessId,
            'room_number':      room.roomNumber,
            'capacity':         room.capacity,
            'room_status':      room.roomStatus,
            'created_at':       room.createdAt ?? DateTime.now().toUtc().toIso8601String(),
            'updated_at':       room.updatedAt ?? DateTime.now().toUtc().toIso8601String(),
            'sync_status':      LocalDatabase.syncSynced,
            'local_updated_at': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      debugPrint('⚠️ _cacheRoomsLocally: $e');
    }
  }

  // ── Create a room ─────────────────────────────────────────────────────────

  Future<RoomResult> createRoom({
    required String businessId,
    required String roomNumber,
    required int capacity,
  }) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      return _createRoomOnline(
        businessId: businessId,
        roomNumber: roomNumber,
        capacity: capacity,
      );
    }
    return RoomResult.err('Room creation requires an internet connection.');
  }

  Future<RoomResult> _createRoomOnline({
    required String businessId,
    required String roomNumber,
    required int capacity,
  }) async {
    final roomId = _generateId();
    final now = DateTime.now().toUtc().toIso8601String();

    // Write locally first
    if (!kIsWeb) {
      await _insertLocalRoom(
        roomId: roomId,
        businessId: businessId,
        roomNumber: roomNumber,
        capacity: capacity,
        syncStatus: LocalDatabase.syncPendingCreate,
        localUpdatedAt: now,
      );
    }

    try {
      final response = await post('/api/business/rooms', {
        'id': roomId,
        'businessId': businessId,
        'roomNumber': roomNumber,
        'capacity': capacity,
      });

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!kIsWeb) {
          await _markRoomSynced(roomId);
          await _incrementLocalTotalRooms(businessId);
        }
        return RoomResult.ok(syncedToCloud: true);
      }
      return RoomResult.ok(syncedToCloud: false);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        return RoomResult.ok(syncedToCloud: false);
      }
      debugPrint('⚠️ _createRoomOnline: API failed, queued for sync — $e');
      return RoomResult.ok(syncedToCloud: false);
    }
  }

  // ── Update a room ─────────────────────────────────────────────────────────

  Future<RoomResult> updateRoom({
    required String roomId,
    required String roomNumber,
    required int capacity,
  }) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      return _updateRoomOnline(
        roomId: roomId,
        roomNumber: roomNumber,
        capacity: capacity,
      );
    }
    return _updateRoomOffline(
      roomId: roomId,
      roomNumber: roomNumber,
      capacity: capacity,
    );
  }

  Future<RoomResult> _updateRoomOnline({
    required String roomId,
    required String roomNumber,
    required int capacity,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    if (!kIsWeb) {
      await _updateLocalRoom(
        roomId: roomId,
        roomNumber: roomNumber,
        capacity: capacity,
        syncStatus: LocalDatabase.syncPendingUpdate,
        localUpdatedAt: now,
      );
    }

    try {
      final response = await put('/api/business/rooms/$roomId', {
        'roomNumber': roomNumber,
        'capacity': capacity,
      });

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!kIsWeb) {
          await _markRoomSynced(roomId);
        }
        return RoomResult.ok(syncedToCloud: true);
      }
      return RoomResult.ok(syncedToCloud: false);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        return RoomResult.ok(syncedToCloud: false);
      }
      debugPrint('⚠️ _updateRoomOnline: API failed, queued for sync — $e');
      return RoomResult.ok(syncedToCloud: false);
    }
  }

  Future<RoomResult> _updateRoomOffline({
    required String roomId,
    required String roomNumber,
    required int capacity,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _updateLocalRoom(
        roomId: roomId,
        roomNumber: roomNumber,
        capacity: capacity,
        syncStatus: LocalDatabase.syncPendingUpdate,
        localUpdatedAt: now,
      );
      return RoomResult.ok();
    } catch (e) {
      debugPrint('❌ updateRoom (offline) error: $e');
      return RoomResult.err('Failed to save room locally.');
    }
  }

  // ── Update room status ────────────────────────────────────────────────────

  Future<RoomResult> updateRoomStatus({
    required String roomId,
    required String roomStatus,
  }) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      return _updateRoomStatusOnline(
        roomId: roomId,
        roomStatus: roomStatus,
      );
    }
    return _updateRoomStatusOffline(
      roomId: roomId,
      roomStatus: roomStatus,
    );
  }

  Future<RoomResult> _updateRoomStatusOnline({
    required String roomId,
    required String roomStatus,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    if (!kIsWeb) {
      final updated = await _updateLocalRoomStatus(
        roomId: roomId,
        roomStatus: roomStatus,
        syncStatus: LocalDatabase.syncPendingUpdate,
        localUpdatedAt: now,
      );
      if (!updated) {
        debugPrint('⚠️ _updateRoomStatusOnline: room $roomId not found locally, will sync via API');
      }
    }

    try {
      final response = await put('/api/business/rooms/$roomId/status', {
        'roomStatus': roomStatus,
      });

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!kIsWeb) {
          await _markRoomSynced(roomId);
        }
        return RoomResult.ok(syncedToCloud: true);
      }
      return RoomResult.ok(syncedToCloud: false);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        return RoomResult.ok(syncedToCloud: false);
      }
      debugPrint('⚠️ _updateRoomStatusOnline: API failed, queued for sync — $e');
      return RoomResult.ok(syncedToCloud: false);
    }
  }

  Future<RoomResult> _updateRoomStatusOffline({
    required String roomId,
    required String roomStatus,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final updated = await _updateLocalRoomStatus(
        roomId: roomId,
        roomStatus: roomStatus,
        syncStatus: LocalDatabase.syncPendingUpdate,
        localUpdatedAt: now,
      );
      if (!updated) {
        return RoomResult.err('Room $roomId not found in local database.');
      }
      return RoomResult.ok();
    } catch (e) {
      debugPrint('❌ updateRoomStatus (offline) error: $e');
      return RoomResult.err('Failed to save room status locally.');
    }
  }

  Future<void> _incrementLocalTotalRooms(String businessId) async {
    // No-op: total_rooms is now computed from rooms table count.
  }

  // ---------------------------------------------------------------------------
  // SQLite helpers
  // ---------------------------------------------------------------------------

  Future<void> _insertLocalRoom({
    required String roomId,
    required String businessId,
    required String roomNumber,
    required int capacity,
    required String syncStatus,
    required String? localUpdatedAt,
  }) async {
    final db = await LocalDatabase.instance.database;

    // Ensure the business exists locally for FK constraint
    final current = SessionService.instance.current;
    if (current != null) {
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

    await db.insert(
      LocalDatabase.tableLocalRooms,
      {
        'id':               roomId,
        'business_id':      businessId,
        'room_number':      roomNumber,
        'capacity':         capacity,
        'room_status':      'vacant',
        'created_at':       DateTime.now().toUtc().toIso8601String(),
        'updated_at':       DateTime.now().toUtc().toIso8601String(),
        'sync_status':      syncStatus,
        'local_updated_at': localUpdatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('💾 SQLite: saved room $roomId (status: $syncStatus, business: $businessId)');
  }

  Future<void> _updateLocalRoom({
    required String roomId,
    required String roomNumber,
    required int capacity,
    required String syncStatus,
    required String? localUpdatedAt,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      LocalDatabase.tableLocalRooms,
      {
        'room_number':      roomNumber,
        'capacity':         capacity,
        'sync_status':      syncStatus,
        'local_updated_at': localUpdatedAt,
      },
      where: 'id = ?',
      whereArgs: [roomId],
    );
  }

  Future<bool> _updateLocalRoomStatus({
    required String roomId,
    required String roomStatus,
    required String syncStatus,
    required String? localUpdatedAt,
  }) async {
    final db = await LocalDatabase.instance.database;
    final rowsAffected = await db.update(
      LocalDatabase.tableLocalRooms,
      {
        'room_status':      roomStatus,
        'sync_status':      syncStatus,
        'local_updated_at': localUpdatedAt,
      },
      where: 'id = ?',
      whereArgs: [roomId],
    );
    if (rowsAffected == 0) {
      debugPrint('⚠️ _updateLocalRoomStatus: room $roomId not found in local_rooms');
    }
    return rowsAffected > 0;
  }

  Future<void> _markRoomSynced(String roomId) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      LocalDatabase.tableLocalRooms,
      {
        'sync_status':      LocalDatabase.syncSynced,
        'local_updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [roomId],
    );
  }

  // ---------------------------------------------------------------------------
  // UUID generator
  // ---------------------------------------------------------------------------

  String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '$now-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  }
}

// ─── Data Models ────────────────────────────────────────────────────────────

class RoomData {
  const RoomData({
    required this.id,
    required this.roomNumber,
    required this.capacity,
    required this.roomStatus,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String roomNumber;
  final int capacity;
  final String roomStatus;
  final String? createdAt;
  final String? updatedAt;
}

class RoomResult {
  final bool success;
  final String? error;
  final bool syncedToCloud;

  const RoomResult._({
    required this.success,
    this.error,
    this.syncedToCloud = false,
  });

  factory RoomResult.ok({bool syncedToCloud = false}) =>
      RoomResult._(success: true, syncedToCloud: syncedToCloud);

  factory RoomResult.err(String error) =>
      RoomResult._(success: false, error: error);
}

// ─── Paginated Result ─────────────────────────────────────────────────────────

class RoomsApiResult<T> {
  const RoomsApiResult.success(this.data) : error = null;
  const RoomsApiResult.failure(this.error) : data = null;

  final T? data;
  final String? error;

  bool get isSuccess => error == null;
}

class RoomsPaginatedData {
  const RoomsPaginatedData({
    required this.data,
    required this.totalCount,
    required this.pageCount,
  });

  final List<RoomData> data;
  final int totalCount;
  final int pageCount;
}
