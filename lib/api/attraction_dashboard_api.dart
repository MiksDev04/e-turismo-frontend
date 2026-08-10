import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'base_api.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class AttractionStats {
  const AttractionStats({
    required this.guestsThisMonth,
    required this.guestsThisYear,
    required this.visitorsToday,
    required this.avgTouristsPerDay,
  });

  final int guestsThisMonth;
  final int guestsThisYear;
  final int visitorsToday;
  final double avgTouristsPerDay;
}

class GenderDistribution {
  const GenderDistribution({
    required this.male,
    required this.female,
    required this.other,
  });

  final int male;
  final int female;
  final int other;

  int get total => male + female + other;
  double get maleRatio => total == 0 ? 0 : male / total;
  double get femaleRatio => total == 0 ? 0 : female / total;
  double get otherRatio => total == 0 ? 0 : other / total;
}

class CountryCount {
  const CountryCount({required this.country, required this.count});

  final String country;
  final int count;
}

class ProvinceCount {
  const ProvinceCount({required this.province, required this.count});

  final String province;
  final int count;
}

class CityCount {
  const CityCount({required this.cityMunicipality, required this.count});

  final String cityMunicipality;
  final int count;
}

class MonthlyCount {
  const MonthlyCount({required this.month, required this.count});

  final int month; // 1–12
  final int count;
}

class AttractionDashboardData {
  const AttractionDashboardData({
    required this.stats,
    required this.genderDistribution,
    required this.topCountries,
    required this.provinces,
    required this.cities,
  });

  final AttractionStats stats;
  final GenderDistribution genderDistribution;
  final List<CountryCount> topCountries;
  final List<ProvinceCount> provinces;
  final List<CityCount> cities;
}

class AttractionDetails {
  const AttractionDetails({
    required this.name,
    required this.types,
    required this.street,
    required this.barangay,
  });

  final String name;
  final List<String> types;
  final String street;
  final String barangay;
}

// ─── API ──────────────────────────────────────────────────────────────────────

class AttractionDashboardApi extends BaseApi {
  AttractionDashboardApi();

  // ── Date helpers ─────────────────────────────────────────────────────────────

  (String start, String end) _dateRange(int month, int year) {
    if (month == 0) {
      return ('$year-01-01', '$year-12-31');
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    final mm = month.toString().padLeft(2, '0');
    final dd = lastDay.toString().padLeft(2, '0');
    return ('$year-$mm-01', '$year-$mm-$dd');
  }

  String _todayDb() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}-$mm-$dd';
  }

  // ===========================================================================
  // PUBLIC — resolveAttractionId
  // ===========================================================================

  Future<String?> resolveAttractionId({bool preferOnline = false}) async {
    if ((preferOnline || ConnectivityService.instance.isOnline) && hasToken) {
      try {
        final online = await _resolveAttractionIdOnline();
        if (online != null && online.isNotEmpty) return online;
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          debugPrint('⚠️ resolveAttractionId: Unauthorized (401). Falling back to session.');
        }
      } catch (_) {
        // Fall through to session fallback.
      }
    }

    final cachedSession =
        SessionService.instance.current ??
        await SessionService.instance.loadAndCache();
    return cachedSession?.attractionId;
  }

  Future<String?> _resolveAttractionIdOnline() async {
    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      return data?['attraction']?['id']?.toString();
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  // PUBLIC — fetchAttractionDetails
  // ===========================================================================

  Future<AttractionDetails> fetchAttractionDetails({
    bool preferOnline = false,
  }) async {
    if ((preferOnline || ConnectivityService.instance.isOnline) && hasToken) {
      try {
        return await _fetchAttractionDetailsOnline();
      } catch (_) {
        // Fall through to session fallback.
      }
    }
    return _detailsFromSession();
  }

  Future<AttractionDetails> _fetchAttractionDetailsOnline() async {
    final response = await get('/api/profile');
    final data = handleResponse(response) as Map<String, dynamic>?;
    final attraction = data?['attraction'] as Map<String, dynamic>?;
    if (attraction == null) return _detailsFromSession();

    return AttractionDetails(
      name: (attraction['attraction_name'] as String?) ?? '',
      types: _parseStringList(attraction['attraction_type']),
      street: (attraction['street'] as String?) ?? '',
      barangay: (attraction['barangay'] as String?) ?? '',
    );
  }

  AttractionDetails _detailsFromSession() {
    final session = SessionService.instance.current;
    return AttractionDetails(
      name: session?.attractionName ?? '',
      types: session?.attractionType ?? const [],
      street: session?.street ?? '',
      barangay: session?.barangay ?? '',
    );
  }

  // ===========================================================================
  // PUBLIC — fetchDashboardData
  // ===========================================================================

  Future<AttractionDashboardData> fetchDashboardData({
    required String attractionId,
    required int month,
    required int year,
  }) async {
    final (yearStart, yearEnd) = _dateRange(0, year);

    // Fetch once with the full year range (superset of month range).
    final allRecords = await _fetchVisitLogs(
      attractionId: attractionId,
      startDate: yearStart,
      endDate: yearEnd,
    );

    final periodRecords = (month == 0)
        ? allRecords
        : allRecords
            .where((r) => _recordInMonth(r, month, year))
            .toList();

    final now = DateTime.now();
    final visitorsToday = (year == now.year)
        ? await _fetchVisitorsToday(attractionId)
        : 0;

    final stats = _computeStats(
      periodRecords: periodRecords,
      yearRecords: allRecords,
      visitorsToday: visitorsToday,
      month: month,
      year: year,
    );

    return _computeDashboardData(stats: stats, records: periodRecords);
  }

  Future<List<Map<String, dynamic>>> _fetchVisitLogs({
    required String attractionId,
    required String startDate,
    required String endDate,
  }) async {
    final response = await get(
      '/api/attraction-dashboard/visit-logs'
      '?attractionId=$attractionId&startDate=$startDate&endDate=$endDate',
    );
    return List<Map<String, dynamic>>.from(handleResponse(response) as List? ?? []);
  }

  Future<int> _fetchVisitorsToday(String attractionId) async {
    final today = _todayDb();
    final records = await _fetchVisitLogs(
      attractionId: attractionId,
      startDate: today,
      endDate: today,
    );
    int sum = 0;
    for (final r in records) {
      sum += _intValue(r, 'guest_count') ?? 0;
    }
    return sum;
  }

  // ===========================================================================
  // SHARED — pure computation
  // ===========================================================================

  bool _recordInMonth(
    Map<String, dynamic> record,
    int month,
    int year,
  ) {
    final date = _stringValue(record, 'visit_date') ?? '';
    if (date.length < 7) return false;
    return date.startsWith('$year-${month.toString().padLeft(2, '0')}');
  }

  AttractionStats _computeStats({
    required List<Map<String, dynamic>> periodRecords,
    required List<Map<String, dynamic>> yearRecords,
    required int visitorsToday,
    required int month,
    required int year,
  }) {
    int monthTotal = 0;
    for (final r in periodRecords) {
      monthTotal += _intValue(r, 'guest_count') ?? 0;
    }

    int yearTotal = 0;
    for (final r in yearRecords) {
      yearTotal += _intValue(r, 'guest_count') ?? 0;
    }

    final days = _periodDays(month, year);
    final avgPerDay = days == 0 ? 0.0 : monthTotal / days;

    return AttractionStats(
      guestsThisMonth: monthTotal,
      guestsThisYear: yearTotal,
      visitorsToday: visitorsToday,
      avgTouristsPerDay: avgPerDay,
    );
  }

  /// Calendar days covered by the selected period. For the current month / year
  /// only the elapsed days count, so the average reflects reality mid-period.
  int _periodDays(int month, int year) {
    final now = DateTime.now();
    if (month == 0) {
      if (year == now.year) {
        return now.difference(DateTime(year, 1, 1)).inDays + 1;
      }
      final last = DateTime(year, 12, 31);
      return last.difference(DateTime(year, 1, 1)).inDays + 1;
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    if (year == now.year && month == now.month) {
      return now.day;
    }
    return lastDay;
  }

  AttractionDashboardData _computeDashboardData({
    required AttractionStats stats,
    required List<Map<String, dynamic>> records,
  }) {
    int male = 0, female = 0, genderOther = 0;
    final countryMap = <String, int>{};
    final provinceMap = <String, int>{};
    final cityMap = <String, int>{};

    for (final r in records) {
      final count = _intValue(r, 'guest_count') ?? 0;
      if (count <= 0) continue;

      final maleCount = _intValue(r, 'male_count');
      final femaleCount = _intValue(r, 'female_count');

      if (maleCount == null && femaleCount == null) {
        // Gender not captured — count the whole row as unknown.
        genderOther += count;
      } else {
        male += maleCount ?? 0;
        female += femaleCount ?? 0;
        final unaccounted = count - (maleCount ?? 0) - (femaleCount ?? 0);
        if (unaccounted > 0) genderOther += unaccounted;
      }

      final country = _stringValue(r, 'country')?.trim() ?? '';
      if (country.isNotEmpty) {
        countryMap[country] = (countryMap[country] ?? 0) + count;
      }

      final province = _stringValue(r, 'province')?.trim() ?? '';
      if (province.isNotEmpty) {
        provinceMap[province] = (provinceMap[province] ?? 0) + count;
      }

      final city = _stringValue(r, 'city_municipality')?.trim() ?? '';
      if (city.isNotEmpty) {
        cityMap[city] = (cityMap[city] ?? 0) + count;
      }
    }

    return AttractionDashboardData(
      stats: stats,
      genderDistribution: GenderDistribution(
        male: male,
        female: female,
        other: genderOther,
      ),
      topCountries: (countryMap.entries
              .map((e) => CountryCount(country: e.key, count: e.value))
              .toList()
            ..sort((a, b) => b.count.compareTo(a.count)))
          .take(5)
          .toList(),
      provinces: (provinceMap.entries
              .map((e) => ProvinceCount(province: e.key, count: e.value))
              .toList()
            ..sort((a, b) => b.count.compareTo(a.count)))
          .take(5)
          .toList(),
      cities: (cityMap.entries
              .map((e) => CityCount(cityMunicipality: e.key, count: e.value))
              .toList()
            ..sort((a, b) => b.count.compareTo(a.count)))
          .take(5)
          .toList(),
    );
  }

  // ===========================================================================
  // PUBLIC — fetchYearlyComparison
  // ===========================================================================

  Future<Map<int, List<MonthlyCount>>> fetchYearlyComparison({
    required String attractionId,
    required List<int> years,
  }) async {
    final result = <int, List<MonthlyCount>>{};

    for (final year in years) {
      final (start, end) = _dateRange(0, year);
      final records = await _fetchVisitLogs(
        attractionId: attractionId,
        startDate: start,
        endDate: end,
      );
      result[year] = _recordsToMonthly(records);
    }

    return result;
  }

  List<MonthlyCount> _recordsToMonthly(List<Map<String, dynamic>> records) {
    final monthMap = <int, int>{};
    for (final r in records) {
      final date = _stringValue(r, 'visit_date') ?? '';
      final month = int.tryParse(date.length >= 7 ? date.substring(5, 7) : '');
      if (month == null) continue;
      final count = _intValue(r, 'guest_count') ?? 0;
      monthMap[month] = (monthMap[month] ?? 0) + count;
    }
    return List.generate(
      12,
      (i) => MonthlyCount(month: i + 1, count: monthMap[i + 1] ?? 0),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((v) => v.toString()).toList();
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((v) => v.toString()).toList();
        }
      } catch (_) {
        // Not JSON — treat as a single value.
      }
      return [value];
    }
    return const [];
  }

  String? _stringValue(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value?.toString();
  }

  int? _intValue(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
