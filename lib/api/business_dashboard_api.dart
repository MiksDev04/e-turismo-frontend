// ignore_for_file: prefer_null_aware_operators, use_null_aware_elements, inference_failure_on_function_invocation

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:app/core/database/local_database.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'package:app/core/utils/datetime_utils.dart';
import 'base_api.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class DashboardStats {
  const DashboardStats({
    required this.guestsThisMonth,
    required this.guestsThisYear,
    required this.avgLengthOfStay,
    required this.totalRooms,
  });

  final int guestsThisMonth;
  final int guestsThisYear;
  final double avgLengthOfStay;
  final int totalRooms;
}

class SexDistribution {
  const SexDistribution({
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
}

class CountryCount {
  const CountryCount({required this.country, required this.count});

  final String country;
  final int count;
}

class MonthlyCount {
  const MonthlyCount({required this.month, required this.count});

  final int month; // 1–12
  final int count;
}

class AgeGroupCount {
  const AgeGroupCount({required this.ageGroup, required this.count});

  final String ageGroup;
  final int count;
}

class PurposeCount {
  const PurposeCount({required this.purpose, required this.count});

  final String purpose;
  final int count;
}

class DashboardData {
  const DashboardData({
    required this.stats,
    required this.sexDistribution,
    required this.topCountries,
    required this.ageGroups,
    required this.purposeOfVisit,
  });

  final DashboardStats stats;
  final SexDistribution sexDistribution;
  final List<CountryCount> topCountries;
  final List<AgeGroupCount> ageGroups;
  final List<PurposeCount> purposeOfVisit;
}

class BusinessDetails {
  const BusinessDetails({
    required this.address,
    required this.barangay,
    required this.totalRooms,
    required this.businessLine,
  });

  final String address;
  final String barangay;
  final int totalRooms;
  final List<String> businessLine;
}

// ─── API ──────────────────────────────────────────────────────────────────────

class BusinessDashboardApi extends BaseApi {
  BusinessDashboardApi();

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

  // ===========================================================================
  // PUBLIC — resolveBusinessId
  // ===========================================================================

  Future<String?> resolveBusinessId({bool preferOnline = false}) async {
    if ((preferOnline || ConnectivityService.instance.isOnline) && hasToken) {
      try {
        final online = await _resolveBusinessIdOnline();
        if (online != null && online.isNotEmpty) return online;
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          debugPrint('⚠️ resolveBusinessId: Unauthorized (401). Falling back to local.');
        }
      } catch (_) {
        // Fall through to local/session fallback.
      }
    }

    final cachedSession =
        SessionService.instance.current ??
        await SessionService.instance.loadAndCache();
    final fromSession = cachedSession?.businessId;
    if (fromSession != null && fromSession.isNotEmpty) return fromSession;

    return _resolveBusinessIdFromLocalDb();
  }

  Future<String?> _resolveBusinessIdOnline() async {
    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      return data?['business']?['id']?.toString();
    } on ApiException catch (e) {
      print('⚠️ resolveBusinessIdOnline: API error ($e). Falling back to local.');
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveBusinessIdFromLocalDb() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      LocalDatabase.tableLocalBusinesses,
      columns: ['id'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as String?;
  }

  // ===========================================================================
  // PUBLIC — fetchBusinessDetails
  // ===========================================================================

  Future<BusinessDetails> fetchBusinessDetails(
    String businessId, {
    bool preferOnline = false,
  }) async {
    final tryOnline = (preferOnline || ConnectivityService.instance.isOnline) && hasToken;

    if (tryOnline) {
      try {
        return await _fetchBusinessDetailsOnline(businessId);
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          debugPrint('⚠️ fetchBusinessDetails: Unauthorized (401). Falling back to local.');
          return await _fetchBusinessDetailsOffline(businessId);
        }
      } catch (_) {
        // Reconnect policy: fallback to SQLite immediately.
      }
    }

    return _fetchBusinessDetailsOffline(businessId);
  }

  Future<BusinessDetails> _fetchBusinessDetailsOnline(String businessId) async {
    try {
      final response = await get('/api/dashboard/details?businessId=$businessId');
      final data = handleResponse(response) as Map<String, dynamic>?;

      if (data == null) {
        return const BusinessDetails(
          address: '',
          barangay: '',
          totalRooms: 0,
          businessLine: [],
        );
      }

      final street = (data['street'] as String?) ?? '';
      final barangay = (data['barangay'] as String?) ?? '';
      final rawBusinessLine = data['business_line'];
      List<String> businessLine = [];
      if (rawBusinessLine is List) {
        businessLine = rawBusinessLine.map((v) => v.toString()).toList();
      } else if (rawBusinessLine is String) {
        try {
          final decoded = jsonDecode(rawBusinessLine);
          if (decoded is List) {
            businessLine = decoded.map((v) => v.toString()).toList();
          } else {
            businessLine = [rawBusinessLine];
          }
        } catch (_) {
          businessLine = [rawBusinessLine];
        }
      }

      return BusinessDetails(
        address: street,
        barangay: barangay,
        totalRooms: (data['total_rooms'] as int?) ?? 0,
        businessLine: businessLine,
      );
    } catch (_) {
      return const BusinessDetails(
        address: '',
        barangay: '',
        totalRooms: 0,
        businessLine: [],
      );
    }
  }

  Future<BusinessDetails> _fetchBusinessDetailsOffline(
    String businessId,
  ) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      LocalDatabase.tableLocalBusinesses,
      where: 'id = ?',
      whereArgs: [businessId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return const BusinessDetails(
        address: '',
        barangay: '',
        totalRooms: 0,
        businessLine: [],
      );
    }

    final row = rows.first;
    final street = (row['street'] as String?) ?? '';
    final barangay = (row['barangay'] as String?) ?? '';
    final rawBusinessLine = row['business_line'] as String?;

    // business_line is stored as a JSON string e.g. '["Hotel","Resort"]'
    List<String> businessLine = [];
    if (rawBusinessLine != null && rawBusinessLine.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBusinessLine);
        if (decoded is List) {
          businessLine = decoded.map((v) => v.toString()).toList();
        }
      } catch (_) {
        businessLine = [rawBusinessLine];
      }
    }

    return BusinessDetails(
      address: street,
      barangay: barangay,
      totalRooms: (row['total_rooms'] as int?) ?? 0,
      businessLine: businessLine,
    );
  }

  // ===========================================================================
  // PUBLIC — fetchDashboardData
  // ===========================================================================

  Future<DashboardData> fetchDashboardData({
    required String businessId,
    required int totalRooms,
    required int month,
    required int year,
    bool preferOnline = false,
  }) async {
    final tryOnline = (preferOnline || ConnectivityService.instance.isOnline) && hasToken;

    if (tryOnline) {
      try {
        return await _fetchDashboardDataOnline(
          businessId: businessId,
          totalRooms: totalRooms,
          month: month,
          year: year,
        );
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          debugPrint('⚠️ fetchDashboardData: Unauthorized (401). Falling back to local.');
          return await _fetchDashboardDataOffline(
            businessId: businessId,
            totalRooms: totalRooms,
            month: month,
            year: year,
          );
        }
      } catch (_) {
        // Reconnect policy: fallback to SQLite immediately.
      }
    }

    return _fetchDashboardDataOffline(
      businessId: businessId,
      totalRooms: totalRooms,
      month: month,
      year: year,
    );
  }

  // ===========================================================================
  // ONLINE — fetch from API
  // ===========================================================================

  Future<DashboardData> _fetchDashboardDataOnline({
    required String businessId,
    required int totalRooms,
    required int month,
    required int year,
  }) async {
    final (start, end) = _dateRange(month, year);
    final (yearStart, yearEnd) = _dateRange(0, year);

    // Fetch once with the full year range (superset of month range).
    final allRecords = await _fetchGuestRecordsOnline(
      businessId: businessId,
      startDate: yearStart,
      endDate: yearEnd,
    );

    // Filter month records client-side to avoid a second API call.
    final periodStart = parseDbDateTime(start);
    final periodEnd = parseDbDateTime(end);
    final periodRecords = (month == 0)
        ? allRecords
        : allRecords.where((r) => _recordOverlapsPeriod(r, periodStart, periodEnd)).toList();

    final yearRecords = allRecords;

    final (yStart, yEnd) = _dateRange(0, year);
    final yearStartDt = parseDbDateTime(yStart);
    final yearEndDt = parseDbDateTime(yEnd);

    final stats = _computeStats(
      periodRecords: periodRecords,
      yearRecords: yearRecords,
      totalRooms: totalRooms,
      periodStart: periodStart,
      periodEnd: periodEnd,
      yearStart: yearStartDt,
      yearEnd: yearEndDt,
    );

    final recordIds = periodRecords
        .map((r) => _stringValue(r, 'id'))
        .whereType<String>()
        .toList();

    final breakdowns = await _fetchBreakdownsOnline(recordIds);

    return _computeDashboardData(
      stats: stats,
      breakdowns: breakdowns,
      periodRecords: periodRecords,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchGuestRecordsOnline({
    required String businessId,
    required String startDate,
    required String endDate,
  }) async {
    final response = await get('/api/dashboard/guest-records?businessId=$businessId&startDate=$startDate&endDate=$endDate');
    return List<Map<String, dynamic>>.from(handleResponse(response) as List? ?? []);
  }

  Future<List<Map<String, dynamic>>> _fetchBreakdownsOnline(
    List<String> recordIds,
  ) async {
    if (recordIds.isEmpty) return [];
    final idsParam = recordIds.join(',');
    final response = await get('/api/dashboard/breakdowns?recordIds=$idsParam');
    return List<Map<String, dynamic>>.from(handleResponse(response) as List? ?? []);
  }

  // ===========================================================================
  // OFFLINE — read from SQLite
  // ===========================================================================

  Future<DashboardData> _fetchDashboardDataOffline({
    required String businessId,
    required int totalRooms,
    required int month,
    required int year,
  }) async {
    final (start, end) = _dateRange(month, year);
    final (yearStart, yearEnd) = _dateRange(0, year);

    // Fetch once with the full year range (superset of month range).
    final allRecords = await _fetchGuestRecordsOffline(
      businessId: businessId,
      startDate: yearStart,
      endDate: yearEnd,
    );

    // Filter month records client-side to avoid a second DB query.
    final periodStart = parseDbDateTime(start);
    final periodEnd = parseDbDateTime(end);
    final periodRecords = (month == 0)
        ? allRecords
        : allRecords.where((r) => _recordOverlapsPeriod(r, periodStart, periodEnd)).toList();

    final yearRecords = allRecords;

    final yearStartDt = parseDbDateTime(yearStart);
    final yearEndDt = parseDbDateTime(yearEnd);

    final stats = _computeStats(
      periodRecords: periodRecords,
      yearRecords: yearRecords,
      totalRooms: totalRooms,
      periodStart: periodStart,
      periodEnd: periodEnd,
      yearStart: yearStartDt,
      yearEnd: yearEndDt,
    );

    final recordIds = periodRecords
        .map((r) => _stringValue(r, 'id'))
        .whereType<String>()
        .toList();

    final breakdowns = await _fetchBreakdownsOffline(recordIds);

    return _computeDashboardData(
      stats: stats,
      breakdowns: breakdowns,
      periodRecords: periodRecords,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchGuestRecordsOffline({
    required String businessId,
    required String startDate,
    required String endDate,
  }) async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      LocalDatabase.tableGuestRecords,
      columns: [
        'id',
        'check_in',
        'check_out',
        'actual_checkout',
        'total_guests',
        'male_count',
        'female_count',
        'purpose_of_visit',
        'lead_country',
        'lead_nationality',
        'lead_is_overseas',
        'lead_birthdate',
        'lead_sex',
      ],
      where:
          'business_id = ? AND is_deleted = 0  '
          'AND COALESCE(actual_checkout, check_out) >= ? AND check_in <= ?',
      whereArgs: [businessId, startDate, endDate],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchBreakdownsOffline(
    List<String> recordIds,
  ) async {
    if (recordIds.isEmpty) return [];

    final db = await LocalDatabase.instance.database;

    final placeholders = recordIds.map((_) => '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT id as guest_record_id, '
      '  lead_country as country, '
      '  lead_sex as sex, '
      '  lead_is_overseas as is_overseas, '
      '  lead_birthdate, '
      '  check_in '
      'FROM ${LocalDatabase.tableGuestRecords} '
      'WHERE id IN ($placeholders)',
      recordIds,
    );

    final breakdowns = <Map<String, dynamic>>[];
    for (final r in rows) {
      final sex = r['sex'] as String? ?? '';
      final isOverseas = (r['is_overseas'] as int?) == 1;
      final country = r['country'] as String?;

      // Compute age group from lead_birthdate + check_in.
      String ageGroup = 'Unknown';
      final birthdateStr = r['lead_birthdate'] as String?;
      final checkInStr = r['check_in'] as String?;
      if (birthdateStr != null && checkInStr != null) {
        final birthdate = tryParseDbDateTime(birthdateStr);
        final checkIn = tryParseDbDateTime(checkInStr);
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

      breakdowns.add({
        'guest_record_id':     r['guest_record_id'],
        'country':             country,
        'sex':                 sex,
        'age_group':           ageGroup,
        'count':               1,
        'is_overseas':         isOverseas,
      });
    }

    return breakdowns;
  }

  // ===========================================================================
  // SHARED — pure computation (same logic for online and offline)
  // ===========================================================================

  DashboardStats _computeStats({
    required List<Map<String, dynamic>> periodRecords,
    required List<Map<String, dynamic>> yearRecords,
    required int totalRooms,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime yearStart,
    required DateTime yearEnd,
  }) {
    int guestsThisMonth = 0;
    for (final r in periodRecords) {
      guestsThisMonth += _recordGuestDays(r, periodStart, periodEnd);
    }

    int guestsThisYear = 0;
    for (final r in yearRecords) {
      guestsThisYear += _recordGuestDays(r, yearStart, yearEnd);
    }

    double avgStay = 0;
    if (periodRecords.isNotEmpty) {
      double totalNights = 0;
      int totalGuests = 0;

      for (final r in periodRecords) {
        final checkInText = _stringValue(r, 'check_in');
        final effectiveCheckOutText =
            _stringValue(r, 'actual_check_out') ??
            _stringValue(r, 'actual_checkout') ??
            _stringValue(r, 'check_out');
        if (checkInText == null || effectiveCheckOutText == null) continue;
        final checkIn = tryParseDbDateTime(checkInText);
        final effectiveCheckOut = tryParseDbDateTime(effectiveCheckOutText);
        if (checkIn == null || effectiveCheckOut == null) continue;

        final nights = effectiveCheckOut.difference(checkIn).inDays;
        final guestCount = (_intValue(r, 'total_guests')) ?? 0;

        totalNights += nights * guestCount;
        totalGuests += guestCount;
      }

      if (totalGuests > 0) avgStay = totalNights / totalGuests;
    }

    return DashboardStats(
      guestsThisMonth: guestsThisMonth,
      guestsThisYear: guestsThisYear,
      avgLengthOfStay: avgStay,
      totalRooms: totalRooms,
    );
  }

  DashboardData _computeDashboardData({
    required DashboardStats stats,
    required List<Map<String, dynamic>> breakdowns,
    required List<Map<String, dynamic>> periodRecords,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    // Build per-record guest-days map for the period
    final recordGuestDays = <String, int>{};
    for (final r in periodRecords) {
      final id = _stringValue(r, 'id');
      if (id != null) {
        recordGuestDays[id] = _recordGuestDays(r, periodStart, periodEnd);
      }
    }

    // Sex distribution uses each record's male_count / female_count (all guests
    // in the party) weighted by guest-days, not just the lead guest's sex.
    int male = 0, female = 0, genderOther = 0;
    for (final record in periodRecords) {
      final id = _stringValue(record, 'id') ?? '';
      final guestDays = recordGuestDays[id] ?? 1;
      final totalGuests = _intValue(record, 'total_guests') ?? 0;
      if (totalGuests <= 0) continue;
      final days = guestDays ~/ totalGuests;
      var maleCount = _intValue(record, 'male_count') ?? 0;
      var femaleCount = _intValue(record, 'female_count') ?? 0;
      if (maleCount + femaleCount == 0) {
        // Defensive fallback for legacy/anomalous rows: count the lead guest only.
        final sex = (_stringValue(record, 'lead_sex') ?? '').toLowerCase();
        if (sex == 'female') {
          femaleCount = 1;
        } else {
          maleCount = 1;
        }
      }
      male += maleCount * days;
      female += femaleCount * days;
      final unaccounted = totalGuests - maleCount - femaleCount;
      if (unaccounted > 0) genderOther += unaccounted * days;
    }

    // Age group distribution — each guest record counts once (lead guest's age),
    // since only the lead guest has a known birthdate. Shared by online/offline.
    final ageGroupMap = <String, int>{};
    for (final b in breakdowns) {
      final ageGroup = _stringValue(b, 'age_group')?.trim() ?? '';
      if (ageGroup.isEmpty) continue;
      ageGroupMap[ageGroup] = (ageGroupMap[ageGroup] ?? 0) + 1;
    }
    final ageGroups =
        ageGroupMap.entries
            .map((e) => AgeGroupCount(ageGroup: e.key, count: e.value))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    // Top 5 countries
    final countryMap = <String, int>{};
    for (final b in breakdowns) {
      final country = _stringValue(b, 'country') ?? 'Unknown';
      final recordId = _stringValue(b, 'guest_record_id') ?? '';
      final guestDays = recordGuestDays[recordId] ?? 1;
      countryMap[country] = (countryMap[country] ?? 0) + guestDays;
    }
    final topCountries =
        (countryMap.entries
                .map((e) => CountryCount(country: e.key, count: e.value))
                .toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .take(5)
            .toList();

    // Purpose of visit
    final purposeMap = <String, int>{};
    for (final record in periodRecords) {
      final purpose = _stringValue(record, 'purpose_of_visit')?.trim() ?? '';
      if (purpose.isEmpty) continue;
      final id = _stringValue(record, 'id') ?? '';
      final guestDays = recordGuestDays[id] ?? 1;
      purposeMap[purpose] = (purposeMap[purpose] ?? 0) + guestDays;
    }
    final purposeOfVisit =
        (purposeMap.entries
                .map((e) => PurposeCount(purpose: e.key, count: e.value))
                .toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .take(5)
            .toList();

    return DashboardData(
      stats: stats,
      sexDistribution: SexDistribution(
        male: male,
        female: female,
        other: genderOther,
      ),
      topCountries: topCountries,
      ageGroups: ageGroups,
      purposeOfVisit: purposeOfVisit,
    );
  }

  // ===========================================================================
  // PUBLIC — fetchYearlyComparison
  // ===========================================================================

  Future<Map<int, List<MonthlyCount>>> fetchYearlyComparison({
    required String businessId,
    required List<int> years,
    bool preferOnline = false,
  }) async {
    final tryOnline = (preferOnline || ConnectivityService.instance.isOnline) && hasToken;

    if (tryOnline) {
      try {
        return await _fetchYearlyComparisonOnline(
          businessId: businessId,
          years: years,
        );
      } catch (_) {
        // Reconnect policy: fallback to SQLite immediately.
      }
    }

    return _fetchYearlyComparisonOffline(
      businessId: businessId,
      years: years,
    );
  }

  Future<Map<int, List<MonthlyCount>>> _fetchYearlyComparisonOnline({
    required String businessId,
    required List<int> years,
  }) async {
    final result = <int, List<MonthlyCount>>{};

    for (final year in years) {
      final (start, end) = _dateRange(0, year);
      final records = await _fetchGuestRecordsOnline(
        businessId: businessId,
        startDate: start,
        endDate: end,
      );
      result[year] = _recordsToMonthly(records, year);
    }

    return result;
  }

  Future<Map<int, List<MonthlyCount>>> _fetchYearlyComparisonOffline({
    required String businessId,
    required List<int> years,
  }) async {
    final result = <int, List<MonthlyCount>>{};

    for (final year in years) {
      final (start, end) = _dateRange(0, year);
      final records = await _fetchGuestRecordsOffline(
        businessId: businessId,
        startDate: start,
        endDate: end,
      );
      result[year] = _recordsToMonthly(records, year);
    }

    return result;
  }

  List<MonthlyCount> _recordsToMonthly(
    List<Map<String, dynamic>> records,
    int year,
  ) {
    final monthMap = <int, int>{};
    final yearStartDt = DateTime(year, 1, 1);
    final yearEndExclusive = DateTime(year + 1, 1, 1);
    for (final r in records) {
      final checkInText = _stringValue(r, 'check_in');
      if (checkInText == null) continue;
      final checkInRaw = tryParseDbDateTime(checkInText);
      if (checkInRaw == null) continue;

      final effectiveCheckOutText =
          _stringValue(r, 'actual_check_out') ??
          _stringValue(r, 'actual_checkout') ??
          _stringValue(r, 'check_out');
      if (effectiveCheckOutText == null) continue;
      final effectiveCheckOutRaw = tryParseDbDateTime(effectiveCheckOutText);
      if (effectiveCheckOutRaw == null) continue;

      final guests = _intValue(r, 'total_guests') ?? 0;
      if (guests <= 0) continue;

      // Spread guest-days across each month the stay overlaps, using the
      // same presence-window semantics as the DAE report: every calendar
      // day from check-in up to (but excluding) the effective check-out.
      // Same-day stays count one day. Days outside the target year are
      // clamped away so prior/next-year stays don't leak into this year.
      final checkIn = DateTime(
        checkInRaw.year,
        checkInRaw.month,
        checkInRaw.day,
      );
      final effectiveCheckOut = DateTime(
        effectiveCheckOutRaw.year,
        effectiveCheckOutRaw.month,
        effectiveCheckOutRaw.day,
      );
      if (effectiveCheckOut.isBefore(checkIn)) continue;

      final nights = effectiveCheckOut.difference(checkIn).inDays;
      final spreadDays = nights + 1;
      final spreadEnd = DateTime(
        checkIn.year,
        checkIn.month,
        checkIn.day + spreadDays,
      );
      final rangeStart = checkIn.isBefore(yearStartDt)
          ? yearStartDt
          : checkIn;
      final rangeEnd = spreadEnd.isAfter(yearEndExclusive)
          ? yearEndExclusive
          : spreadEnd;
      if (!rangeEnd.isAfter(rangeStart)) continue;

      var monthCursor = DateTime(rangeStart.year, rangeStart.month, 1);
      final lastMonth = DateTime(rangeEnd.year, rangeEnd.month, 1);
      while (!monthCursor.isAfter(lastMonth)) {
        final monthEndExclusive = DateTime(
          monthCursor.year,
          monthCursor.month + 1,
          1,
        );
        final segStart = rangeStart.isAfter(monthCursor)
            ? rangeStart
            : monthCursor;
        final segEnd = rangeEnd.isBefore(monthEndExclusive)
            ? rangeEnd
            : monthEndExclusive;
        if (segEnd.isAfter(segStart)) {
          monthMap[monthCursor.month] =
              (monthMap[monthCursor.month] ?? 0) +
                  guests * segEnd.difference(segStart).inDays;
        }
        monthCursor = DateTime(
          monthCursor.year,
          monthCursor.month + 1,
          1,
        );
      }
    }
    return List.generate(
      12,
      (i) => MonthlyCount(month: i + 1, count: monthMap[i + 1] ?? 0),
    );
  }

  // ===========================================================================
  // PUBLIC — generateCsv
  // ===========================================================================

  Future<String> generateCsv({
    required String businessId,
    required String businessName,
    required int month,
    required int year,
  }) async {
    final (start, end) = _dateRange(month, year);

    final records = ConnectivityService.instance.isOnline
        ? await _fetchGuestRecordsOnline(
            businessId: businessId,
            startDate: start,
            endDate: end,
          )
        : await _fetchGuestRecordsOffline(
            businessId: businessId,
            startDate: start,
            endDate: end,
          );

    final recordIds = records
        .map((r) => _stringValue(r, 'id'))
        .whereType<String>()
        .toList();

    final breakdowns = ConnectivityService.instance.isOnline
        ? await _fetchBreakdownsOnline(recordIds)
        : await _fetchBreakdownsOffline(recordIds);

    final recordMap = <String, Map<String, dynamic>>{
      for (final r in records)
        if (_stringValue(r, 'id') case final id?) id: r,
    };

    final buf = StringBuffer()
      ..writeln('Business,$businessName')
      ..writeln('Period,${month == 0 ? 'Full Year' : _monthName(month)} $year')
      ..writeln()
      ..writeln(
        'Check In,Check Out,Total Guests,Guest Days,'
        'Country,Sex,Age Group,Guest Days',
      );

    final periodStart = parseDbDateTime(start);
    final periodEnd = parseDbDateTime(end);

    for (final b in breakdowns) {
      final recordId = _stringValue(b, 'guest_record_id');
      if (recordId == null) continue;
      final rec = recordMap[recordId];
      if (rec == null) continue;
      final guestDays = _recordGuestDays(rec, periodStart, periodEnd);
      final totalGuests = _intValue(rec, 'total_guests') ?? 0;
      if (totalGuests <= 0) continue;
      final days = guestDays ~/ totalGuests;
      var maleCount = _intValue(rec, 'male_count') ?? 0;
      var femaleCount = _intValue(rec, 'female_count') ?? 0;
      if (maleCount + femaleCount == 0) {
        // Defensive fallback for legacy/anomalous rows: count the lead guest only.
        final sex = (_stringValue(rec, 'lead_sex') ?? '').toLowerCase();
        if (sex == 'female') {
          femaleCount = 1;
        } else {
          maleCount = 1;
        }
      }

      final checkIn = _stringValue(rec, 'check_in') ?? '';
      final checkOut = _stringValue(rec, 'check_out') ?? '';
      final country = _csvCell(_stringValue(b, 'country') ?? 'Unknown');
      final ageGroup = _stringValue(b, 'age_group') ?? '';

      if (maleCount > 0) {
        final sexDays = maleCount * days;
        buf.writeln(
          [checkIn, checkOut, maleCount, sexDays, country, 'Male', ageGroup, sexDays].join(','),
        );
      }
      if (femaleCount > 0) {
        final sexDays = femaleCount * days;
        buf.writeln(
          [checkIn, checkOut, femaleCount, sexDays, country, 'Female', ageGroup, sexDays].join(','),
        );
      }
      final unaccounted = totalGuests - maleCount - femaleCount;
      if (unaccounted > 0) {
        final sexDays = unaccounted * days;
        buf.writeln(
          [checkIn, checkOut, unaccounted, sexDays, country, 'Other', ageGroup, sexDays].join(','),
        );
      }
    }

    return buf.toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String? _stringValue(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value == null ? null : value.toString();
  }

  int? _intValue(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  /// Compute guest-days for a record within [rangeStart, rangeEnd].
  ///
  /// A guest is counted on every calendar day of presence — check-in through
  /// the effective check-out (inclusive), which is `actual_check_out` when
  /// present, otherwise `check_out`. Check-in Aug 6 / check-out Aug 8 counts
  /// 3 days; same-day stays count a single day.
  int _recordGuestDays(
    Map<String, dynamic> record,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final checkInText = _stringValue(record, 'check_in');
    if (checkInText == null) return 0;
    final checkInRaw = tryParseDbDateTime(checkInText);
    if (checkInRaw == null) return 0;

    final effectiveCheckOutText =
        _stringValue(record, 'actual_check_out') ??
        _stringValue(record, 'actual_checkout') ??
        _stringValue(record, 'check_out');
    if (effectiveCheckOutText == null) return 0;
    final effectiveCheckOutRaw = tryParseDbDateTime(effectiveCheckOutText);
    if (effectiveCheckOutRaw == null) return 0;

    final guests = _intValue(record, 'total_guests') ?? 0;
    if (guests <= 0) return 0;

    final checkIn = DateTime(checkInRaw.year, checkInRaw.month, checkInRaw.day);
    final effectiveCheckOut = DateTime(
      effectiveCheckOutRaw.year,
      effectiveCheckOutRaw.month,
      effectiveCheckOutRaw.day,
    );
    if (effectiveCheckOut.isBefore(checkIn)) return 0;

    final nights = effectiveCheckOut.difference(checkIn).inDays;
    final spreadDays = nights + 1;
    final spreadEnd = DateTime(
      checkIn.year,
      checkIn.month,
      checkIn.day + spreadDays,
    );
    final rangeEndExclusive = DateTime(
      rangeEnd.year,
      rangeEnd.month,
      rangeEnd.day + 1,
    );

    final start = checkIn.isBefore(rangeStart) ? rangeStart : checkIn;
    final end = spreadEnd.isAfter(rangeEndExclusive)
        ? rangeEndExclusive
        : spreadEnd;
    if (!end.isAfter(start)) return 0;

    return guests * end.difference(start).inDays;
  }

  /// Check whether a record's stay overlaps with [rangeStart, rangeEnd].
  bool _recordOverlapsPeriod(
    Map<String, dynamic> record,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final checkInText = _stringValue(record, 'check_in');
    if (checkInText == null) return false;
    final checkIn = tryParseDbDateTime(checkInText);
    if (checkIn == null) return false;

    final effectiveCheckOutText =
        _stringValue(record, 'actual_check_out') ??
        _stringValue(record, 'actual_checkout') ??
        _stringValue(record, 'check_out');
    if (effectiveCheckOutText == null) return false;
    final effectiveCheckOut = tryParseDbDateTime(effectiveCheckOutText);
    if (effectiveCheckOut == null) return false;

    return !checkIn.isAfter(rangeEnd) && !effectiveCheckOut.isBefore(rangeStart);
  }

  String _csvCell(String value) => value.contains(',') ? '"$value"' : value;

  String _monthName(int month) => const [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month];
}
