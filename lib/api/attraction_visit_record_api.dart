import 'package:flutter/foundation.dart';
import 'package:app/core/services/offline_service.dart';
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

  /// Fetch paginated visit records for the current attraction.
  ///
  /// Parameters mirror the backend query-string contract:
  ///   page, pageSize, dateFrom, dateTo, origin
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
    if (!ConnectivityService.instance.isOnline || !hasToken) {
      return const ApiResult.failure(
        'Attraction accounts are online-only. Please connect to the internet.',
      );
    }

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

    try {
      final response = await get(uri.toString());
      final body = handleResponse(response) as Map<String, dynamic>;

      final rows = body['data'] as List? ?? [];
      final totalCount = (body['totalCount'] as num?)?.toInt() ?? 0;
      final pageCount = (body['pageCount'] as num?)?.toInt() ?? 0;

      final data = rows
          .map((r) => VisitRecord.fromJson(r as Map<String, dynamic>))
          .toList();

      return ApiResult.success((
        data: data,
        totalCount: totalCount,
        pageCount: pageCount,
      ));
    } on ApiException catch (e) {
      debugPrint('fetchVisitRecords: API error ${e.statusCode} - ${e.message}');
      if (e.statusCode == 401) {
        return const ApiResult.failure('Session expired. Please log in again.');
      }
      return ApiResult.failure(e.message);
    } catch (e) {
      debugPrint('fetchVisitRecords: unexpected error - $e');
      return const ApiResult.failure('Failed to load visit records.');
    }
  }

  /// Fetch a single visit record by its UUID.
  Future<ApiResult<VisitRecord>> fetchVisitRecordById(String id) async {
    if (!ConnectivityService.instance.isOnline || !hasToken) {
      return const ApiResult.failure(
        'Attraction accounts are online-only. Please connect to the internet.',
      );
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
      return ApiResult.failure(e.message);
    } catch (e) {
      debugPrint('fetchVisitRecordById: unexpected error - $e');
      return const ApiResult.failure('Failed to load visit record.');
    }
  }
}
