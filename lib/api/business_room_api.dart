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
    final response = await get('/api/business/rooms?businessId=$businessId');
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
    )).toList();
  }

  Future<void> _cacheRoomsLocally(String businessId, List<RoomData> rooms) async {
    if (kIsWeb) return;
    try {
      final db = await LocalDatabase.instance.database;
      for (final room in rooms) {
        await db.insert(
          LocalDatabase.tableLocalRooms,
          {
            'id':               room.id,
            'business_id':      businessId,
            'room_number':      room.roomNumber,
            'capacity':         room.capacity,
            'room_status':      room.roomStatus,
            'created_at':       DateTime.now().toUtc().toIso8601String(),
            'updated_at':       DateTime.now().toUtc().toIso8601String(),
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
    return _createRoomOffline(
      businessId: businessId,
      roomNumber: roomNumber,
      capacity: capacity,
    );
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

  Future<RoomResult> _createRoomOffline({
    required String businessId,
    required String roomNumber,
    required int capacity,
  }) async {
    try {
      final roomId = _generateId();
      final now = DateTime.now().toUtc().toIso8601String();

      await _insertLocalRoom(
        roomId: roomId,
        businessId: businessId,
        roomNumber: roomNumber,
        capacity: capacity,
        syncStatus: LocalDatabase.syncPendingCreate,
        localUpdatedAt: now,
      );

      return RoomResult.ok();
    } catch (e) {
      debugPrint('❌ createRoom (offline) error: $e');
      return RoomResult.err('Failed to save room locally.');
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
      await _updateLocalRoomStatus(
        roomId: roomId,
        roomStatus: roomStatus,
        syncStatus: LocalDatabase.syncPendingUpdate,
        localUpdatedAt: now,
      );
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
      await _updateLocalRoomStatus(
        roomId: roomId,
        roomStatus: roomStatus,
        syncStatus: LocalDatabase.syncPendingUpdate,
        localUpdatedAt: now,
      );
      return RoomResult.ok();
    } catch (e) {
      debugPrint('❌ updateRoomStatus (offline) error: $e');
      return RoomResult.err('Failed to save room status locally.');
    }
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

  Future<void> _updateLocalRoomStatus({
    required String roomId,
    required String roomStatus,
    required String syncStatus,
    required String? localUpdatedAt,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      LocalDatabase.tableLocalRooms,
      {
        'room_status':      roomStatus,
        'sync_status':      syncStatus,
        'local_updated_at': localUpdatedAt,
      },
      where: 'id = ?',
      whereArgs: [roomId],
    );
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
  });

  final String id;
  final String roomNumber;
  final int capacity;
  final String roomStatus;
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
