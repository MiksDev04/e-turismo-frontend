// ignore_for_file: inference_failure_on_function_invocation

import 'dart:convert';
import 'base_api.dart';
import '../core/utils/datetime_utils.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class AdminDashboardStats {
  const AdminDashboardStats({
    required this.activeAccommodations,
    required this.touristsThisPeriod,
    required this.pendingRegistrations,
    required this.touristsThisYear,
  });

  final int activeAccommodations;
  final int touristsThisPeriod;
  final int pendingRegistrations;
  final int touristsThisYear;
}

typedef DashboardStats = AdminDashboardStats;

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
}

typedef SexDistribution = GenderDistribution;

class AgeGroupCount {
  const AgeGroupCount({required this.ageGroup, required this.count});

  final String ageGroup;
  final int count;
}

class NationalityCount {
  const NationalityCount({required this.nationality, required this.count});

  final String nationality;
  final int count;
}

typedef CountryCount = NationalityCount;

class AccommodationTypeCount {
  const AccommodationTypeCount({required this.type, required this.count});

  final String type;
  final int count;
}

class PurposeCount {
  const PurposeCount({required this.purpose, required this.count});

  final String purpose;
  final int count;
}

class ComplianceData {
  const ComplianceData({required this.compliant, required this.nonCompliant});

  final int compliant;
  final int nonCompliant;

  double get rate {
    final total = compliant + nonCompliant;
    return total == 0 ? 0 : compliant / total;
  }
}

class AdminDashboardData {
  const AdminDashboardData({
    required this.stats,
    required this.genderDistribution,
    required this.ageGroups,
    required this.topNationalities,
    required this.compliance,
    required this.accommodationTypes,
    required this.purposeOfVisit,
  });

  final AdminDashboardStats stats;
  final GenderDistribution genderDistribution;
  final List<AgeGroupCount> ageGroups;
  final List<NationalityCount> topNationalities;
  final ComplianceData compliance;
  final List<AccommodationTypeCount> accommodationTypes;
  final List<PurposeCount> purposeOfVisit;
}

typedef DashboardData = AdminDashboardData;

class AdminProfile {
  const AdminProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.role,
  });

  final String id;
  final String fullName;
  final String phone;
  final String email;
  final String role;

  String get displayLabel => '$fullName • Admin';
}

class MonthlyCount {
  const MonthlyCount({required this.month, required this.count});

  final int month; // 1–12
  final int count;
}

// ─── API ──────────────────────────────────────────────────────────────────────

class AdminDashboardApi extends BaseApi {
  (String start, String end) _dateRange(int month, int year) {
    if (month == 0) {
      return ('$year-01-01', '$year-12-31');
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    final mm = month.toString().padLeft(2, '0');
    final dd = lastDay.toString().padLeft(2, '0');
    return ('$year-$mm-01', '$year-$mm-$dd');
  }

  Future<AdminProfile?> fetchAdminProfile(String adminId) async {
    final response = await get('/api/profile');
    final data = handleResponse(response);

    if (data != null && data['user'] != null) {
      final user = data['user'];
      return AdminProfile(
        id: user['id'].toString(),
        fullName: (user['full_name'] as String?) ?? '',
        phone: (user['phone'] as String?) ?? '',
        email: (user['email'] as String?) ?? '',
        role: (user['role'] as String?) ?? 'admin',
      );
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> _fetchGuestRecords({
    required String startDate,
    required String endDate,
  }) async {
    final response = await get(
      '/api/dashboard/guest-records?startDate=$startDate&endDate=$endDate',
    );
    final data = handleResponse(response);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Map<String, dynamic>>> _fetchBreakdowns(
    List<String> recordIds,
  ) async {
    if (recordIds.isEmpty) return [];
    final response = await get(
      '/api/dashboard/breakdowns?recordIds=${recordIds.join(',')}',
    );
    final data = handleResponse(response);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<Map<String, int>> _fetchStats() async {
    final response = await get('/api/dashboard/stats');
    final data = handleResponse(response);
    return {
      'active': (data['activeAccommodations'] as num).toInt(),
      'pending': (data['pendingRegistrations'] as num).toInt(),
    };
  }

  List<String> _extractBusinessLines(Object? value) {
    if (value == null) return const [];
    
    List<dynamic> raw = [];
    if (value is List) {
      raw = value;
    } else if (value is String) {
      if (value.startsWith('[')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is List) raw = decoded;
        } catch (_) {}
      } else {
        return value.split(RegExp(r'[,|\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).map(_toTitleCase).toList();
      }
    }

    return raw.map((e) => (e?.toString() ?? '').trim()).where((e) => e.isNotEmpty).map(_toTitleCase).toList();
  }

  Future<List<AccommodationTypeCount>> _fetchAccommodationTypes(
    List<Map<String, dynamic>> periodRecords,
  ) async {
    final businessIds =
        periodRecords
            .map((record) => record['business_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
    if (businessIds.isEmpty) return const [];

    final response = await get(
      '/api/dashboard/business-lines?businessIds=${businessIds.join(',')}',
    );
    final data = handleResponse(response);
    final businesses = List<Map<String, dynamic>>.from(data as List);

    final linesByBusiness = <String, List<String>>{};
    for (final business in businesses) {
      final id = business['id'].toString();
      linesByBusiness[id] = _extractBusinessLines(business['business_line']);
    }

    final typeMap = <String, int>{};

    for (final record in periodRecords) {
      final businessId = record['business_id']?.toString();
      final lines = linesByBusiness[businessId] ?? const [];
      if (lines.isEmpty) continue;

      final guestCount = (record['total_guests'] as num?)?.toInt() ?? 0;
      for (final type in lines) {
        typeMap[type] = (typeMap[type] ?? 0) + guestCount;
      }
    }

    return typeMap.entries
        .map((e) => AccommodationTypeCount(type: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  Future<AdminDashboardData> fetchDashboardData({
    required int month,
    required int year,
  }) async {
    final (start, end) = _dateRange(month, year);
    final (yearStart, yearEnd) = _dateRange(0, year);

    final response = await get(
      '/api/dashboard/summary?startDate=$start&endDate=$end&yearStart=$yearStart&yearEnd=$yearEnd',
    );
    final data = handleResponse(response);

    final periodRecords =
        List<Map<String, dynamic>>.from(data['periodRecords'] as List);
    final yearRecords =
        List<Map<String, dynamic>>.from(data['yearRecords'] as List);

    final periodStart = parseDbDateTime(start);
    final periodEnd = parseDbDateTime(end);
    final yearStartDt = parseDbDateTime(yearStart);
    final yearEndDt = parseDbDateTime(yearEnd);

    int touristsThisPeriod = 0;
    for (final r in periodRecords) {
      touristsThisPeriod += _recordGuestDays(r, periodStart, periodEnd);
    }
    int touristsThisYear = 0;
    for (final r in yearRecords) {
      touristsThisYear += _recordGuestDays(r, yearStartDt, yearEndDt);
    }

    final stats = data['stats'] as Map<String, dynamic>;
    final activeAccommodations = (stats['activeAccommodations'] as num).toInt();
    final pendingRegistrations = (stats['pendingRegistrations'] as num).toInt();

    final breakdowns =
        List<Map<String, dynamic>>.from(data['breakdowns'] as List);

    // Build per-record guest-days map for the period
    final recordGuestDays = <String, int>{};
    for (final r in periodRecords) {
      final id = r['id']?.toString();
      if (id != null) {
        recordGuestDays[id] = _recordGuestDays(r, periodStart, periodEnd);
      }
    }

    int male = 0, female = 0, other = 0;
    for (final breakdown in breakdowns) {
      final sex = (breakdown['sex'] as String? ?? '').toLowerCase();
      final recordId = breakdown['guest_record_id']?.toString() ?? '';
      final guestDays = recordGuestDays[recordId] ?? 1;
      if (sex == 'male') {
        male += guestDays;
      } else if (sex == 'female') {
        female += guestDays;
      } else {
        other += guestDays;
      }
    }

    final ageGroupMap = <String, int>{};
    for (final breakdown in breakdowns) {
      final ageGroup = (breakdown['age_group'] as String? ?? '').trim();
      if (ageGroup.isEmpty) continue;
      final label = _toTitleCase(ageGroup);
      final recordId = breakdown['guest_record_id']?.toString() ?? '';
      final guestDays = recordGuestDays[recordId] ?? 1;
      ageGroupMap[label] = (ageGroupMap[label] ?? 0) + guestDays;
    }
    final ageGroups =
        ageGroupMap.entries
            .map((e) => AgeGroupCount(ageGroup: e.key, count: e.value))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    final nationalityMap = <String, int>{};
    for (final breakdown in breakdowns) {
      final country = (breakdown['country'] as String? ?? '').trim();
      if (country.isEmpty) continue;
      final label = _toTitleCase(country);
      final recordId = breakdown['guest_record_id']?.toString() ?? '';
      final guestDays = recordGuestDays[recordId] ?? 1;
      nationalityMap[label] = (nationalityMap[label] ?? 0) + guestDays;
    }
    final topNationalities =
        (nationalityMap.entries
                .map(
                  (entry) => NationalityCount(
                    nationality: entry.key,
                    count: entry.value,
                  ),
                )
                .toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .take(5)
            .toList();

    final purposeMap = <String, int>{};
    for (final record in periodRecords) {
      final purpose = (record['purpose_of_visit'] as String? ?? '').trim();
      if (purpose.isEmpty) continue;
      final label = _toTitleCase(purpose);
      final id = record['id']?.toString() ?? '';
      final guestDays = recordGuestDays[id] ?? 1;
      purposeMap[label] = (purposeMap[label] ?? 0) + guestDays;
    }
    final purposeOfVisit =
        (purposeMap.entries
                .map((e) => PurposeCount(purpose: e.key, count: e.value))
                .toList()
              ..sort((a, b) => b.count.compareTo(a.count)))
            .take(5)
            .toList();

    final businessLines =
        List<Map<String, dynamic>>.from(data['businessLines'] as List);
    final linesByBusiness = <String, List<String>>{};
    for (final business in businessLines) {
      final id = business['id'].toString();
      linesByBusiness[id] = _extractBusinessLines(business['business_line']);
    }
    final typeMap = <String, int>{};
    for (final record in periodRecords) {
      final businessId = record['business_id']?.toString();
      final lines = linesByBusiness[businessId] ?? const [];
      if (lines.isEmpty) continue;
      final id = record['id']?.toString() ?? '';
      final guestDays = recordGuestDays[id] ?? 1;
      for (final type in lines) {
        typeMap[type] = (typeMap[type] ?? 0) + guestDays;
      }
    }
    final accommodationTypes = typeMap.entries
        .map((e) => AccommodationTypeCount(type: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return AdminDashboardData(
      stats: AdminDashboardStats(
        activeAccommodations: activeAccommodations,
        touristsThisPeriod: touristsThisPeriod,
        pendingRegistrations: pendingRegistrations,
        touristsThisYear: touristsThisYear,
      ),
      genderDistribution: GenderDistribution(
        male: male,
        female: female,
        other: other,
      ),
      ageGroups: ageGroups,
      topNationalities: topNationalities,
      compliance: ComplianceData(
        compliant: activeAccommodations,
        nonCompliant: pendingRegistrations,
      ),
      accommodationTypes: accommodationTypes,
      purposeOfVisit: purposeOfVisit,
    );
  }

  Future<Map<int, List<MonthlyCount>>> fetchYearlyComparison({
    required List<int> years,
  }) async {
    final result = <int, List<MonthlyCount>>{};

    for (final year in years) {
      final (start, end) = _dateRange(0, year);
      final records = await _fetchGuestRecords(startDate: start, endDate: end);

      final yearStartDt = parseDbDateTime(start);
      final yearEndDt = parseDbDateTime(end);

      final monthMap = <int, int>{};
      for (final record in records) {
        final checkInText = record['check_in']?.toString();
        if (checkInText == null) continue;
        final checkInRaw = tryParseDbDateTime(checkInText);
        if (checkInRaw == null) continue;

        final effectiveCheckOutText =
            record['actual_check_out']?.toString() ??
            record['actual_checkout']?.toString() ??
            record['check_out']?.toString();
        if (effectiveCheckOutText == null) continue;
        final effectiveCheckOutRaw = tryParseDbDateTime(effectiveCheckOutText);
        if (effectiveCheckOutRaw == null) continue;

        final guests = (record['total_guests'] as num?)?.toInt() ?? 0;
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
        final effectiveCheckOutDate = DateTime(
          effectiveCheckOutRaw.year,
          effectiveCheckOutRaw.month,
          effectiveCheckOutRaw.day,
        );
        if (effectiveCheckOutDate.isBefore(checkIn)) continue;

        final nights = effectiveCheckOutDate.difference(checkIn).inDays;
        final spreadDays = nights + 1;
        final spreadEnd = DateTime(
          checkIn.year,
          checkIn.month,
          checkIn.day + spreadDays,
        );
        final yearEndExclusive = DateTime(
          yearEndDt.year,
          yearEndDt.month,
          yearEndDt.day + 1,
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

      result[year] = List.generate(
        12,
        (index) =>
            MonthlyCount(month: index + 1, count: monthMap[index + 1] ?? 0),
      );
    }

    return result;
  }

  Future<String> generateCsv({
    required String businessName,
    required int month,
    required int year,
  }) async {
    final (start, end) = _dateRange(month, year);
    final records = await _fetchGuestRecords(startDate: start, endDate: end);
    final recordIds = records.map((record) => record['id'].toString()).toList();
    final breakdowns = await _fetchBreakdowns(recordIds);

    final recordMap = {
      for (final record in records) record['id'].toString(): record,
    };

    final buffer = StringBuffer()
      ..writeln('Business,$businessName')
      ..writeln('Period,${month == 0 ? 'Full Year' : _monthName(month)} $year')
      ..writeln()
      ..writeln(
        'Check In,Check Out,Total Guests,Guest Days,'
        'Country,Sex,Age Group,Guest Days',
      );

    final periodStart = parseDbDateTime(start);
    final periodEnd = parseDbDateTime(end);

    for (final breakdown in breakdowns) {
      final record = recordMap[breakdown['guest_record_id'].toString()];
      if (record == null) continue;
      final guestDays = _recordGuestDays(record, periodStart, periodEnd);
      final row = [
        record['check_in'],
        record['check_out'],
        record['total_guests'],
        guestDays,
        _csvCell(breakdown['country'] as String? ?? ''),
        breakdown['sex'],
        breakdown['age_group'],
        guestDays,
      ];
      buffer.writeln(row.join(','));
    }

    return buffer.toString();
  }

  String _csvCell(String value) => value.contains(',') ? '"$value"' : value;

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
    final checkInText = record['check_in']?.toString();
    if (checkInText == null) return 0;
    final checkInRaw = tryParseDbDateTime(checkInText);
    if (checkInRaw == null) return 0;

    final effectiveCheckOutText =
        record['actual_check_out']?.toString() ??
        record['actual_checkout']?.toString() ??
        record['check_out']?.toString();
    if (effectiveCheckOutText == null) return 0;
    final effectiveCheckOutRaw = tryParseDbDateTime(effectiveCheckOutText);
    if (effectiveCheckOutRaw == null) return 0;

    final guests = (record['total_guests'] as num?)?.toInt() ?? 0;
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

  String _toTitleCase(String s) => s
      .split('_')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
