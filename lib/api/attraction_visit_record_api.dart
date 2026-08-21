import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'base_api.dart';

// ─── Result Wrapper ───────────────────────────────────────────────────────────

class ApiResult<T> {
  const ApiResult.success(this.data) : error = null;
  const ApiResult.failure(this.error) : data = null;

  final T? data;
  final String? error;

  bool get isSuccess => error == null;
}

// ─── Visit Record Model ───────────────────────────────────────────────────────

class VisitRecord {
  const VisitRecord({
    required this.id,
    required this.attractionId,
    required this.visitDate,
    required this.guestCount,
    this.maleCount,
    this.femaleCount,
    this.country,
    this.province,
    this.cityMunicipality,
    this.nationality,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String attractionId;
  final DateTime visitDate;
  final int guestCount;
  final int? maleCount;
  final int? femaleCount;
  final String? country;
  final String? province;
  final String? cityMunicipality;
  final String? nationality;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory VisitRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) {
        try {
          // Handle both 'YYYY-MM-DD' and 'YYYY-MM-DDTHH:mm:ss...'
          final trimmed = v.trim();
          if (trimmed.length >= 10) {
            return DateTime.parse(trimmed);
          }
        } catch (_) {}
      }
      return null;
    }

    return VisitRecord(
      id: json['id'] as String? ?? '',
      attractionId: json['attraction_id'] as String? ??
          json['attractionId'] as String? ??
          '',
      visitDate: parseDate(json['visit_date'] ?? json['visitDate']) ??
          DateTime.now(),
      guestCount: (json['guest_count'] as num?)?.toInt() ?? 0,
      maleCount: (json['male_count'] as num?)?.toInt(),
      femaleCount: (json['female_count'] as num?)?.toInt(),
      country: json['country'] as String?,
      province: json['province'] as String?,
      cityMunicipality: json['city_municipality'] as String? ??
          json['cityMunicipality'] as String?,
      nationality: json['nationality'] as String?,
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }

  bool get isForeign => country != null && country != 'Philippines';
}

// ─── Visit Record API ─────────────────────────────────────────────────────────

class AttractionVisitRecordApi extends BaseApi {
  AttractionVisitRecordApi();

  Future<String?> resolveAttractionId() async {
    final session =
        SessionService.instance.current ??
        await SessionService.instance.loadAndCache();
    return session?.attractionId;
  }

  /// Fetch paginated visit records for the current attraction.
  ///
  /// Parameters mirror the backend query-string contract:
  ///   page, pageSize, dateFrom, dateTo, origin
  ///
  /// Online: fetches from the API, back-fills the SQLite cache and merges
  /// locally-pending rows into the returned page. Any failure falls through
  /// to the local store so the page stays usable offline.
  Future<ApiResult<({
    List<VisitRecord> data,
    int totalCount,
    int pageCount,
  })>> fetchVisitRecords({
    int page = 1,
    int pageSize = 10,
    String? dateFrom,
    String? dateTo,
    String? origin,
  }) async {
    if (ConnectivityService.instance.isOnline && hasToken) {
      try {
        return await _fetchOnline(
          page: page,
          pageSize: pageSize,
          dateFrom: dateFrom,
          dateTo: dateTo,
          origin: origin,
        );
      } on ApiException catch (e) {
        debugPrint('fetchVisitRecords: API error ${e.statusCode} - ${e.message}');
        if (kIsWeb) {
          if (e.statusCode == 401) {
            return const ApiResult.failure('Session expired. Please log in again.');
          }
          return ApiResult.failure(e.message);
        }
        // Fall through to the local store below.
      } catch (e) {
        debugPrint('fetchVisitRecords: unexpected error - $e');
        if (kIsWeb) {
          return const ApiResult.failure('Failed to load visit records.');
        }
      }
    }

    if (kIsWeb) {
      return const ApiResult.failure(
        'Attraction accounts are online-only. Please connect to the internet.',
      );
    }

    return _fetchLocal(
      page: page,
      pageSize: pageSize,
      dateFrom: dateFrom,
      dateTo: dateTo,
      origin: origin,
    );
  }

  // ---------------------------------------------------------------------------
  // ONLINE
  // ---------------------------------------------------------------------------

  Future<ApiResult<({
    List<VisitRecord> data,
    int totalCount,
    int pageCount,
  })>> _fetchOnline({
    required int page,
    required int pageSize,
    String? dateFrom,
    String? dateTo,
    String? origin,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (dateFrom != null) queryParams['dateFrom'] = dateFrom;
    if (dateTo != null) queryParams['dateTo'] = dateTo;
    if (origin != null && origin != 'all') queryParams['origin'] = origin;

    final uri = Uri.parse('/api/attraction/visit-records').replace(
      queryParameters: queryParams,
    );

    final response = await get(uri.toString());
    final body = handleResponse(response) as Map<String, dynamic>;

    final rows = body['data'] as List? ?? [];
    final totalCount = (body['totalCount'] as num?)?.toInt() ?? 0;
    final pageCount = (body['pageCount'] as num?)?.toInt() ?? 0;

    final data = rows
        .map((r) => VisitRecord.fromJson(r as Map<String, dynamic>))
        .toList();

    // Cache back-fill + merge locally-pending rows into the returned page.
    try {
      await _backfillCache(rows);

      final attractionId = await resolveAttractionId();
      if (attractionId != null && attractionId.isNotEmpty) {
        final pending = await _fetchPendingLocalRecords(
          attractionId,
          excludeIds: data.map((r) => r.id).toSet(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          origin: origin,
        );
        data.addAll(pending);
        data.sort((a, b) => b.visitDate.compareTo(a.visitDate));
      }
    } catch (e) {
      debugPrint('⚠️ fetchVisitRecords: local merge failed — $e');
    }

    return ApiResult.success((
      data: data,
      totalCount: totalCount,
      pageCount: pageCount,
    ));
  }

  Future<void> _backfillCache(List rows) async {
    final db = await LocalDatabase.instance.database;

    for (final raw in rows) {
      final r = Map<String, dynamic>.from(raw as Map);
      final entryId = r['id'] as String?;
      if (entryId == null || entryId.isEmpty) continue;

      // Never clobber locally-pending rows with cloud copies.
      final existing = await db.query(
        LocalDatabase.tableVisitEntries,
        columns: ['sync_status'],
        where: 'id = ?',
        whereArgs: [entryId],
        limit: 1,
      );
      if (existing.isNotEmpty &&
          existing.first['sync_status'] != LocalDatabase.syncSynced) {
        continue;
      }

      await db.insert(
        LocalDatabase.tableVisitEntries,
        {
          'id':                entryId,
          'attraction_id':     r['attraction_id'] ?? r['attractionId'],
          'visit_date':        r['visit_date'] ?? r['visitDate'],
          'guest_count':
              (r['guest_count'] as num?)?.toInt() ??
              (r['guestCount'] as num?)?.toInt() ??
              0,
          'male_count':
              (r['male_count'] as num?)?.toInt() ??
              (r['maleCount'] as num?)?.toInt() ??
              0,
          'female_count':
              (r['female_count'] as num?)?.toInt() ??
              (r['femaleCount'] as num?)?.toInt() ??
              0,
          'country':           r['country'],
          'province':          r['province'],
          'city_municipality': r['city_municipality'] ?? r['cityMunicipality'],
          'nationality':       r['nationality'],
          'created_at':        r['created_at'] ?? r['createdAt'],
          'updated_at':        r['updated_at'] ?? r['updatedAt'],
          'sync_status':       LocalDatabase.syncSynced,
          'local_updated_at':  null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<List<VisitRecord>> _fetchPendingLocalRecords(
    String attractionId, {
    Set<String> excludeIds = const {},
    String? dateFrom,
    String? dateTo,
    String? origin,
  }) async {
    final db = await LocalDatabase.instance.database;

    final conditions = <String>[
      'attraction_id = ?',
      'sync_status != ?',
    ];
    final args = <dynamic>[attractionId, LocalDatabase.syncSynced];

    _applyDateFilters(conditions, args, dateFrom: dateFrom, dateTo: dateTo);
    _applyOriginFilter(conditions, args, origin);

    final rows = await db.query(
      LocalDatabase.tableVisitEntries,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'visit_date DESC',
    );

    return rows
        .where((row) => !excludeIds.contains(row['id'] as String))
        .map(_recordFromLocalRow)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // OFFLINE — read entirely from SQLite.
  // ---------------------------------------------------------------------------

  Future<ApiResult<({
    List<VisitRecord> data,
    int totalCount,
    int pageCount,
  })>> _fetchLocal({
    required int page,
    required int pageSize,
    String? dateFrom,
    String? dateTo,
    String? origin,
  }) async {
    try {
      final attractionId = await resolveAttractionId();
      if (attractionId == null || attractionId.isEmpty) {
        return const ApiResult.failure(
          'No attraction account associated with this user.',
        );
      }

      final db = await LocalDatabase.instance.database;

      final conditions = <String>['attraction_id = ?'];
      final args = <dynamic>[attractionId];

      _applyDateFilters(conditions, args, dateFrom: dateFrom, dateTo: dateTo);
      _applyOriginFilter(conditions, args, origin);

      final where = conditions.join(' AND ');

      final totalCount = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM ${LocalDatabase.tableVisitEntries} WHERE $where',
              args,
            ),
          ) ??
          0;

      final rows = await db.query(
        LocalDatabase.tableVisitEntries,
        where: where,
        whereArgs: args,
        orderBy: 'visit_date DESC',
        limit: pageSize,
        offset: (page - 1) * pageSize,
      );

      final data = rows.map(_recordFromLocalRow).toList();
      final pageCount = pageSize > 0 ? (totalCount / pageSize).ceil() : 0;

      return ApiResult.success((
        data: data,
        totalCount: totalCount,
        pageCount: pageCount,
      ));
    } catch (e) {
      debugPrint('❌ fetchVisitRecords (offline): $e');
      return const ApiResult.failure('Failed to load visit records.');
    }
  }

  // ── Shared filter helpers ───────────────────────────────────────────────────

  void _applyDateFilters(
    List<String> conditions,
    List<dynamic> args, {
    String? dateFrom,
    String? dateTo,
  }) {
    if (dateFrom != null && dateFrom.isNotEmpty) {
      conditions.add('visit_date >= ?');
      args.add(dateFrom);
    }
    if (dateTo != null && dateTo.isNotEmpty) {
      conditions.add('visit_date <= ?');
      args.add(dateTo);
    }
  }

  void _applyOriginFilter(
    List<String> conditions,
    List<dynamic> args,
    String? origin,
  ) {
    if (origin == 'local') {
      conditions.add("(country IS NULL OR country = 'Philippines')");
    } else if (origin == 'foreign') {
      conditions.add("(country IS NOT NULL AND country != 'Philippines')");
    }
  }

  VisitRecord _recordFromLocalRow(Map<String, dynamic> row) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) {
        try {
          final trimmed = v.trim();
          if (trimmed.length >= 10) {
            return DateTime.parse(trimmed);
          }
        } catch (_) {}
      }
      return null;
    }

    return VisitRecord(
      id: row['id'] as String? ?? '',
      attractionId: row['attraction_id'] as String? ?? '',
      visitDate: parseDate(row['visit_date']) ?? DateTime.now(),
      guestCount: (row['guest_count'] as num?)?.toInt() ?? 0,
      maleCount: (row['male_count'] as num?)?.toInt(),
      femaleCount: (row['female_count'] as num?)?.toInt(),
      country: row['country'] as String?,
      province: row['province'] as String?,
      cityMunicipality: row['city_municipality'] as String?,
      nationality: row['nationality'] as String?,
      createdAt: parseDate(row['created_at']),
      updatedAt: parseDate(row['updated_at']),
    );
  }

  // ---------------------------------------------------------------------------
  // Single-record fetch — falls back to SQLite when offline.
  // ---------------------------------------------------------------------------

  /// Fetch a single visit record by its UUID.
  Future<ApiResult<VisitRecord>> fetchVisitRecordById(String id) async {
    if (!ConnectivityService.instance.isOnline || !hasToken) {
      if (kIsWeb) {
        return const ApiResult.failure(
          'Attraction accounts are online-only. Please connect to the internet.',
        );
      }
      return _fetchRecordByIdLocal(id);
    }

    try {
      final response = await get('/api/attraction/visit-records/$id');
      final body = handleResponse(response) as Map<String, dynamic>;
      return ApiResult.success(VisitRecord.fromJson(body));
    } on ApiException catch (e) {
      debugPrint('fetchVisitRecordById: API error ${e.statusCode} - ${e.message}');
      if (e.statusCode == 401) {
        return const ApiResult.failure('Session expired. Please log in again.');
      }
      if (e.statusCode == 404) {
        return const ApiResult.failure('Visit record not found.');
      }
      if (kIsWeb) {
        return ApiResult.failure(e.message);
      }
      return _fetchRecordByIdLocal(id);
    } catch (e) {
      debugPrint('fetchVisitRecordById: unexpected error - $e');
      if (kIsWeb) {
        return const ApiResult.failure('Failed to load visit record.');
      }
      return _fetchRecordByIdLocal(id);
    }
  }

  Future<ApiResult<VisitRecord>> _fetchRecordByIdLocal(String id) async {
    try {
      final db = await LocalDatabase.instance.database;
      final rows = await db.query(
        LocalDatabase.tableVisitEntries,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return const ApiResult.failure('Visit record not found.');
      }
      return ApiResult.success(_recordFromLocalRow(rows.first));
    } catch (e) {
      debugPrint('❌ fetchVisitRecordById (offline): $e');
      return const ApiResult.failure('Failed to load visit record.');
    }
  }
}
