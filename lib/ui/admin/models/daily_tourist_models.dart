// lib/ui/admin/models/daily_tourist_models.dart

/// Per-day tourist counts for one entity (business or attraction) in a month.
class DailyTouristsResult {
  const DailyTouristsResult({
    required this.year,
    required this.month,
    required this.byDay,
    required this.total,
  });

  final int year;
  final int month;

  /// day-of-month (1..daysInMonth) -> tourist count. Days with no data map to 0.
  final Map<int, int> byDay;

  /// Sum of all daily counts for the month.
  final int total;

  /// Number of days in [month]/[year] (handles leap years via DateTime).
  int get daysInMonth => DateTime(year, month + 1, 0).day;

  /// Convenience accessor; 0 when the day has no entry.
  int countFor(int day) => byDay[day] ?? 0;

  /// Reads the backend envelope: { data: { year, month, days: [ {day, tourists} ], total } }.
  factory DailyTouristsResult.fromMap(Map<String, dynamic> map) {
    final data = (map['data'] as Map<String, dynamic>?) ?? const {};
    final year = (data['year'] as num?)?.toInt() ?? 0;
    final month = (data['month'] as num?)?.toInt() ?? 0;
    final total = (data['total'] as num?)?.toInt() ?? 0;

    final byDay = <int, int>{};
    final rawDays = data['days'];
    if (rawDays is List) {
      for (final entry in rawDays) {
        if (entry is! Map) continue;
        final day = (entry['day'] as num?)?.toInt();
        if (day == null) continue;
        byDay[day] = (entry['tourists'] as num?)?.toInt() ?? 0;
      }
    }

    return DailyTouristsResult(
      year: year,
      month: month,
      byDay: byDay,
      total: total,
    );
  }
}
