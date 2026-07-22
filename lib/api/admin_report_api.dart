// ignore_for_file: deprecated_member_use

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'base_api.dart';

export 'base_api.dart';

// ─── Report Batch Model ──────────────────────────────────────────────────────

class ReportBatch {
  const ReportBatch({
    required this.id,
    required this.reportType,
    required this.reportVariant,
    required this.periodYear,
    required this.periodMonths,
    required this.createdAt,
    this.lastViewedAt,
    this.lastGeneratedAt,
    this.requestedByName,
    this.periodLabel,
  });

  final String id;
  final String reportType;
  final String reportVariant;
  final int periodYear;
  final List<int> periodMonths;
  final DateTime createdAt;
  final DateTime? lastViewedAt;
  final DateTime? lastGeneratedAt;
  final String? requestedByName;
  final String? periodLabel;

  String get shortId => id.replaceAll('-', '').substring(0, 8).toUpperCase();

  String get variantLabel {
    switch (reportVariant) {
      case 'daily':
        return 'Daily Breakdown';
      case 'summary':
        return 'Country Summary';
      case 'series':
        return 'Series';
      default:
        return reportVariant;
    }
  }

  String get displayPeriod => periodLabel ?? _computePeriodLabel();

  String _computePeriodLabel() {
    final sorted = [...periodMonths]..sort();
    if (sorted.length == 12) return '$periodYear';
    if (sorted.length == 1) return '${_monthName(sorted[0])} $periodYear';
    final abbr = sorted.map((m) => _monthAbbr(m)).join('-');
    return '$abbr $periodYear';
  }

  static String _monthName(int m) {
    const n = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return (m >= 1 && m <= 12) ? n[m] : '\u2014';
  }

  static String _monthAbbr(int m) {
    const a = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return (m >= 1 && m <= 12) ? a[m] : '\u2014';
  }

  static ReportBatch fromJson(Map<String, dynamic> json) => ReportBatch(
    id: json['id'] as String,
    reportType: json['report_type'] as String? ?? 'dae',
    reportVariant: json['report_variant'] as String,
    periodYear: json['period_year'] as int,
    periodMonths: (json['period_months'] as List).map((e) => e as int).toList(),
    createdAt: DateTime.parse(json['created_at'] as String),
    lastViewedAt: json['last_viewed_at'] != null
        ? DateTime.parse(json['last_viewed_at'] as String)
        : null,
    lastGeneratedAt: json['last_generated_at'] != null
        ? DateTime.parse(json['last_generated_at'] as String)
        : null,
    requestedByName: json['requested_by_name'] as String?,
    periodLabel: json['period_label'] as String?,
  );
}

// ─── Report View Data Models ─────────────────────────────────────────────────

class ReportViewResponse {
  const ReportViewResponse({
    required this.batch,
    required this.establishments,
    required this.totals,
  });

  final BatchInfo batch;
  final List<EstablishmentReport> establishments;
  final ReportTotals totals;

  static ReportViewResponse fromJson(Map<String, dynamic> json) =>
      ReportViewResponse(
        batch: BatchInfo.fromJson(json['batch'] as Map<String, dynamic>),
        establishments: (json['establishments'] as List)
            .map((e) => EstablishmentReport.fromJson(e as Map<String, dynamic>))
            .toList(),
        totals: ReportTotals.fromJson(json['totals'] as Map<String, dynamic>),
      );
}

class BatchInfo {
  const BatchInfo({
    required this.id,
    required this.reportType,
    required this.reportVariant,
    required this.periodYear,
    required this.periodMonths,
  });

  final String id;
  final String reportType;
  final String reportVariant;
  final int periodYear;
  final List<int> periodMonths;

  static BatchInfo fromJson(Map<String, dynamic> json) => BatchInfo(
    id: json['id'] as String,
    reportType: json['reportType'] as String,
    reportVariant: json['reportVariant'] as String,
    periodYear: json['periodYear'] as int,
    periodMonths: (json['periodMonths'] as List).map((e) => e as int).toList(),
  );
}

class EstablishmentReport {
  const EstablishmentReport({
    required this.businessId,
    required this.businessName,
    required this.totalRooms,
    this.aeId,
    this.region,
    this.cityMunicipality,
    this.province,
    this.businessLine,
    this.monthData,
    this.seriesData,
  });

  final String businessId;
  final String businessName;
  final int totalRooms;
  final String? aeId;
  final String? region;
  final String? cityMunicipality;
  final String? province;
  final List<String>? businessLine;

  /// For daily/summary: single MonthData object
  final MonthData? monthData;

  /// For series: list of {month, data} objects
  final List<MonthSeriesEntry>? seriesData;

  static EstablishmentReport fromJson(Map<String, dynamic> json) {
    final md = json['monthData'];
    final sd = json['seriesData'];

    return EstablishmentReport(
      businessId: json['businessId'] as String,
      businessName: json['businessName'] as String,
      totalRooms: json['totalRooms'] as int? ?? 0,
      aeId: json['aeId'] as String?,
      region: json['region'] as String?,
      cityMunicipality: json['cityMunicipality'] as String?,
      province: json['province'] as String?,
      businessLine: json['businessLine'] != null
          ? (json['businessLine'] as List).map((e) => e.toString()).toList()
          : null,
      monthData: md != null ? MonthData.fromJson(md as Map<String, dynamic>) : null,
      seriesData: sd != null
          ? (sd as List)
              .map((e) => MonthSeriesEntry.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}

class MonthSeriesEntry {
  const MonthSeriesEntry({required this.month, required this.data});
  final int month;
  final MonthData data;

  static MonthSeriesEntry fromJson(Map<String, dynamic> json) =>
      MonthSeriesEntry(
        month: json['month'] as int,
        data: MonthData.fromJson(json['data'] as Map<String, dynamic>),
      );
}

class MonthData {
  const MonthData({
    required this.month,
    this.countryByDay,
    this.residentsByDay,
    this.sexByDay,
    this.roomsOccupied,
    this.guestNightsByDay,
    this.guestNights,
  });

  final int month;
  final Map<String, Map<String, int>>? countryByDay;
  final Map<String, Map<String, int>>? residentsByDay;
  final Map<String, Map<String, Map<String, int>>>? sexByDay;
  final Map<String, int>? roomsOccupied;
  final Map<String, int>? guestNightsByDay;
  final int? guestNights;

  /// Convenience: get grand total for the month (day key "0")
  int get grandTotal {
    final r = residentsByDay?['0'];
    if (r == null) return 0;
    return (r['philippine_resident_filipino'] ?? 0) +
        (r['philippine_resident_foreign'] ?? 0) +
        (r['listed_foreign_resident'] ?? 0) +
        (r['unlisted_foreign_resident'] ?? 0) +
        (r['unspecified_guest'] ?? 0) +
        (r['overseas_filipino'] ?? 0);
  }

  /// Convenience: total rooms occupied for the month
  int get totalRoomsOccupied =>
      roomsOccupied?.values.fold<int>(0, (a, b) => a + b) ?? 0;

  static MonthData fromJson(Map<String, dynamic> json) {
    return MonthData(
      month: json['month'] as int,
      countryByDay: _parseNestedMap(json['countryByDay']),
      residentsByDay: _parseNestedMap(json['residentsByDay']),
      sexByDay: _parseSexByDay(json['sexByDay']),
      roomsOccupied: _parseIntMap(json['roomsOccupied']),
      guestNightsByDay: _parseIntMap(json['guestNightsByDay']),
      guestNights: json['guestNights'] as int?,
    );
  }

  static Map<String, Map<String, int>>? _parseNestedMap(dynamic json) {
    if (json == null) return null;
    final result = <String, Map<String, int>>{};
    (json as Map<String, dynamic>).forEach((key, value) {
      if (value is Map) {
        result[key] = _parseIntMap(value) ?? {};
      }
    });
    return result;
  }

  static Map<String, int>? _parseIntMap(dynamic json) {
    if (json == null) return null;
    final result = <String, int>{};
    (json as Map<String, dynamic>).forEach((key, value) {
      result[key] = (value as num?)?.toInt() ?? 0;
    });
    return result;
  }

  static Map<String, Map<String, Map<String, int>>>? _parseSexByDay(dynamic json) {
    if (json == null) return null;
    final result = <String, Map<String, Map<String, int>>>{};
    (json as Map<String, dynamic>).forEach((dayKey, sexMap) {
      if (sexMap is Map) {
        final dayData = <String, Map<String, int>>{};
        sexMap.forEach((sex, bucketMap) {
          if (bucketMap is Map) {
            dayData[sex] = _parseIntMap(bucketMap) ?? {};
          }
        });
        result[dayKey] = dayData;
      }
    });
    return result;
  }
}

class ReportTotals {
  const ReportTotals({
    this.totalRooms,
    this.countryByDay,
    this.residentsByDay,
    this.sexByDay,
    this.roomsOccupied,
    this.guestNights,
  });

  final int? totalRooms;
  final Map<String, Map<String, int>>? countryByDay;
  final Map<String, Map<String, int>>? residentsByDay;
  final Map<String, Map<String, Map<String, int>>>? sexByDay;
  final Map<String, int>? roomsOccupied;
  final int? guestNights;

  static ReportTotals fromJson(Map<String, dynamic> json) => ReportTotals(
    totalRooms: json['totalRooms'] as int?,
    countryByDay: MonthData._parseNestedMap(json['countryByDay']),
    residentsByDay: MonthData._parseNestedMap(json['residentsByDay']),
    sexByDay: MonthData._parseSexByDay(json['sexByDay']),
    roomsOccupied: MonthData._parseIntMap(json['roomsOccupied']),
    guestNights: json['guestNights'] as int?,
  );
}

// ─── Parameters ──────────────────────────────────────────────────────────────

class CreateBatchParams {
  final String reportType;
  final String reportVariant;
  final int periodYear;
  final List<int> periodMonths;

  const CreateBatchParams({
    this.reportType = 'dae',
    required this.reportVariant,
    required this.periodYear,
    required this.periodMonths,
  });

  Map<String, dynamic> toJson() => {
    'reportType': reportType,
    'reportVariant': reportVariant,
    'periodYear': periodYear,
    'periodMonths': periodMonths,
  };
}

class ViewReportParams {
  final String reportType;
  final String reportVariant;
  final int periodYear;
  final List<int> periodMonths;

  const ViewReportParams({
    this.reportType = 'dae',
    required this.reportVariant,
    required this.periodYear,
    required this.periodMonths,
  });

  Map<String, String> toQueryParams() => {
    'reportType': reportType,
    'reportVariant': reportVariant,
    'periodYear': periodYear.toString(),
    'periodMonths': jsonEncode(periodMonths),
  };
}

class DownloadReportParams {
  final String reportType;
  final String reportVariant;
  final int periodYear;
  final List<int> periodMonths;
  final String format;

  const DownloadReportParams({
    this.reportType = 'dae',
    required this.reportVariant,
    required this.periodYear,
    required this.periodMonths,
    this.format = 'xlsx',
  });

  Map<String, dynamic> toJson() => {
    'reportType': reportType,
    'reportVariant': reportVariant,
    'periodYear': periodYear,
    'periodMonths': periodMonths,
    'format': format,
  };
}

// ─── Report Service ──────────────────────────────────────────────────────────

class ReportService extends BaseApi {
  static const _maxCacheEntries = 20;
  static final LinkedHashMap<String, Uint8List> _fileCache = LinkedHashMap<String, Uint8List>();

  /// Fetches paginated report batches from the backend.
  Future<({List<ReportBatch> data, int totalCount, int pageCount})>
      fetchReportBatches({
    int page = 1,
    int pageSize = 10,
    String? type,
    String? variant,
    String? year,
    String? month,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (type != null && type != 'all') queryParams['type'] = type;
    if (variant != null && variant != 'all') queryParams['variant'] = variant;
    if (year != null && year != 'all' && year != 'All Years') {
      queryParams['year'] = year;
    }
    if (month != null && month != 'all' && month != 'All Months') {
      queryParams['month'] = month;
    }

    final uri =
        Uri.parse('/api/admin/reports').replace(queryParameters: queryParams);
    final response = await get(uri.toString());
    final body = handleResponse(response) as Map<String, dynamic>;
    final list = body['data'] as List;
    final totalCount = (body['totalCount'] as num?)?.toInt() ?? 0;
    final pageCount = (body['pageCount'] as num?)?.toInt() ?? 0;
    final data =
        list.map((r) => ReportBatch.fromJson(r as Map<String, dynamic>)).toList();
    return (data: data, totalCount: totalCount, pageCount: pageCount);
  }

  /// Creates a new report batch (no file generation).
  /// Returns the batchId. If a matching batch already exists, returns the existing one.
  Future<String> createBatch(CreateBatchParams params) async {
    final body = params.toJson();
    final response = await post('/api/admin/reports', body);
    final result = handleResponse(response) as Map<String, dynamic>;
    return result['batchId'] as String;
  }

  /// Fetches live report data as JSON for viewing in the UI.
  Future<ReportViewResponse> viewReport(ViewReportParams params) async {
    final queryParams = params.toQueryParams();
    final uri = Uri.parse('/api/admin/reports/view')
        .replace(queryParameters: queryParams);
    final response = await get(uri.toString(), timeout: const Duration(seconds: 120));
    final body = handleResponse(response) as Map<String, dynamic>;
    return ReportViewResponse.fromJson(body);
  }

  /// Downloads a report file (xlsx or pdf) as raw bytes.
  Future<Uint8List> downloadReport(DownloadReportParams params) async {
    final body = params.toJson();
    final endpoint = '/api/admin/reports/download';

    // Use http.post directly to get raw bytes (BaseApi.post decodes JSON)
    final uri = Uri.parse('$baseUrl$endpoint');
    final response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      String message = 'Failed to download report';
      try {
        final errBody = jsonDecode(response.body);
        message = errBody['error'] ?? errBody['message'] ?? message;
      } catch (_) {}
      throw ApiException(message, response.statusCode);
    }
  }

  // ── File cache (kept for backward compatibility) ──────────────────────────

  static void _cacheFile(String key, Uint8List bytes) {
    if (_fileCache.length >= _maxCacheEntries) {
      _fileCache.remove(_fileCache.keys.first);
    }
    _fileCache[key] = bytes;
  }

  Uint8List? getCachedFile(String fileUrl) {
    final uri = fileUrl.startsWith('http')
        ? Uri.parse(fileUrl)
        : Uri.parse('$baseUrl$fileUrl');
    return _fileCache[uri.toString()];
  }

  bool isCached(String fileUrl) {
    final uri = fileUrl.startsWith('http')
        ? Uri.parse(fileUrl)
        : Uri.parse('$baseUrl$fileUrl');
    return _fileCache.containsKey(uri.toString());
  }

  /// Downloads a file from a URL (kept for backward compatibility).
  Future<Uint8List> downloadReportFile(String fileUrl) async {
    final uri = fileUrl.startsWith('http')
        ? Uri.parse(fileUrl)
        : Uri.parse('$baseUrl$fileUrl');
    final key = uri.toString();

    final cached = _fileCache[key];
    if (cached != null) return cached;

    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      final bytes = response.bodyBytes;
      _cacheFile(key, bytes);
      return bytes;
    } else {
      throw Exception('Failed to download report: ${response.statusCode}');
    }
  }
}
