import 'dart:convert';
import 'base_api.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum ActivityStatus { active, lowActivity, inactive, noActivity }

enum BusinessStatusLevel { approved, warning, suspended }

// ─── Models ───────────────────────────────────────────────────────────────────

class BusinessActivityRecord {
  const BusinessActivityRecord({
    required this.id,
    required this.businessName,
    required this.businessLine,
    required this.businessStatus,
    required this.totalRecords,
    required this.totalGuests,
    this.lastActivity,
    required this.activityStatus,
  });

  final String id;
  final String businessName;
  final List<String> businessLine;
  final BusinessStatusLevel businessStatus;
  final int totalRecords;
  final int totalGuests;
  final DateTime? lastActivity;
  final ActivityStatus activityStatus;

  factory BusinessActivityRecord.fromJson(Map<String, dynamic> json) {
    final rawLine = json['business_line'];
    List<String> lines = [];
    if (rawLine is List) {
      lines = rawLine.map((v) => v.toString()).toList();
    } else if (rawLine is String && rawLine.startsWith('[')) {
      try {
        final decoded = jsonDecode(rawLine);
        if (decoded is List) {
          lines = decoded.map((v) => v.toString()).toList();
        }
      } catch (_) {}
    }

    return BusinessActivityRecord(
      id: json['id'] as String,
      businessName: json['business_name'] as String,
      businessLine: lines,
      businessStatus: _parseBusinessStatus(json['business_status'] as String),
      totalRecords: (json['total_records'] as num).toInt(),
      totalGuests: (json['total_guests'] as num).toInt(),
      lastActivity: json['last_activity'] != null
          ? DateTime.tryParse(json['last_activity'] as String)
          : null,
      activityStatus: _parseActivityStatus(json['activity_status'] as String),
    );
  }

  static BusinessStatusLevel _parseBusinessStatus(String raw) {
    switch (raw) {
      case 'warning':
        return BusinessStatusLevel.warning;
      case 'suspended':
        return BusinessStatusLevel.suspended;
      case 'approved':
      case 'active':
      default:
        return BusinessStatusLevel.approved;
    }
  }

  static ActivityStatus _parseActivityStatus(String raw) {
    switch (raw) {
      case 'active':
        return ActivityStatus.active;
      case 'low_activity':
        return ActivityStatus.lowActivity;
      case 'inactive':
        return ActivityStatus.inactive;
      case 'no_activity':
      default:
        return ActivityStatus.noActivity;
    }
  }

  bool get isCompliant => activityStatus == ActivityStatus.active;
  bool get hasWarning => businessStatus == BusinessStatusLevel.warning;
  bool get isSuspended => businessStatus == BusinessStatusLevel.suspended;

  String get businessLineLabel {
    if (businessLine.isEmpty) return '—';
    return businessLine
        .map(_formatBusinessLine)
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  static String _formatBusinessLine(String raw) {
    switch (raw.toLowerCase()) {
      case 'hotel':
        return 'Hotel';
      case 'resort':
        return 'Resort';
      case 'motel':
        return 'Motel';
      case 'pension_inn':
        return 'Pension Inn';
      case 'youth_hostel':
        return 'Youth Hostel';
      case 'apartment':
        return 'Apartment';
      case 'others':
        return 'Others';
      default:
        // Handle camelCase or other formats
        return raw.split('_').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    }
  }

  BusinessActivityRecord copyWith({BusinessStatusLevel? businessStatus}) {
    return BusinessActivityRecord(
      id: id,
      businessName: businessName,
      businessLine: businessLine,
      businessStatus: businessStatus ?? this.businessStatus,
      totalRecords: totalRecords,
      totalGuests: totalGuests,
      lastActivity: lastActivity,
      activityStatus: activityStatus,
    );
  }
}

/// Holds the aggregated guest total for a single check-in date.
class DailyGuestStat {
  const DailyGuestStat({
    required this.date,
    required this.totalGuests,
  });

  final DateTime date;
  final int totalGuests;
}

// ─── API ──────────────────────────────────────────────────────────────────────

class AdminComplianceApi extends BaseApi {
  /// Fetches all rows from the [business_activity_summary] view.
  Future<List<BusinessActivityRecord>> fetchActivitySummary() async {
    final response = await get('/api/admin/compliance/activity-summary');
    final data = handleResponse(response) as List<dynamic>;

    return data
        .map((e) => BusinessActivityRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Updates the [status] column of a business row in [businesses].
  /// Sends a [reason] for the status change, used for notification messages.
  Future<void> updateBusinessStatus(
    String businessId,
    BusinessStatusLevel newStatus, {
    required String reason,
    required String messageContent,
  }) async {
    final raw = switch (newStatus) {
      BusinessStatusLevel.approved => 'approved',
      BusinessStatusLevel.warning => 'warning',
      BusinessStatusLevel.suspended => 'suspended',
    };

    final response = await put('/api/admin/compliance/business-status/$businessId', {
      'status': raw,
      'reason': reason,
      'messageContent': messageContent,
    });
    handleResponse(response);
  }

  /// Fetches and aggregates total guests per [check_in] date for [businessId]
  /// within the given [month] (1–12) and [year].
  Future<List<DailyGuestStat>> fetchDailyStats(
    String businessId,
    int month,
    int year,
  ) async {
    final response = await get(
      '/api/admin/compliance/daily-stats/$businessId?month=$month&year=$year',
    );
    final data = handleResponse(response) as List<dynamic>;

    return data.map((row) {
      return DailyGuestStat(
        date: DateTime.parse(row['check_in'] as String),
        totalGuests: (row['total_guests'] as num).toInt(),
      );
    }).toList();
  }
}
