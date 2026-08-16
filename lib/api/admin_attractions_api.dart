// lib/api/admin_attractions_api.dart

import 'package:flutter/foundation.dart';
import 'package:app/api/base_api.dart';
import 'package:app/ui/admin/models/attraction_models.dart';

// ─── Result wrapper ───────────────────────────────────────────────────────────

class AttractionResult {
  final bool success;
  final String? error;

  const AttractionResult._({required this.success, this.error});
  factory AttractionResult.ok() => const AttractionResult._(success: true);
  factory AttractionResult.err(String error) =>
      AttractionResult._(success: false, error: error);
}

// ─── Export row model ─────────────────────────────────────────────────────────

class AttractionExportRow {
  const AttractionExportRow({
    required this.attractionName,
    required this.attractionTypes,
    required this.street,
    required this.barangay,
    required this.ownerName,
    required this.phone,
  });

  final String attractionName;
  final String attractionTypes;
  final String street;
  final String barangay;
  final String ownerName;
  final String phone;
}

// ─── Ranking row model ────────────────────────────────────────────────────────

class AttractionRankingRow {
  const AttractionRankingRow({
    required this.attractionId,
    required this.attractionName,
    required this.totalVisitors,
    required this.rank,
  });

  final String attractionId;
  final String attractionName;
  final int totalVisitors;
  final int rank;
}

// ─── API ──────────────────────────────────────────────────────────────────────

class AdminAttractionApi extends BaseApi {
  // ── Fetch paginated attractions with joined profile ──────────────────────
  Future<({
    List<Attraction> data,
    int totalCount,
    int pageCount,
  })> fetchAll({
    int page = 1,
    int pageSize = 10,
    String? status,
    String? searchQuery,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (status != null && status != 'all') queryParams['status'] = status;
      if (searchQuery != null && searchQuery.isNotEmpty) {
        queryParams['search'] = searchQuery;
      }

      final uri = Uri.parse('/api/admin/attractions').replace(queryParameters: queryParams);
      final response = await get(uri.toString());
      final body = handleResponse(response);
      final list = body['data'] as List;
      final totalCount = (body['totalCount'] as num?)?.toInt() ?? 0;
      final pageCount = (body['pageCount'] as num?)?.toInt() ?? 0;
      final data = list
          .map((e) => Attraction.fromMap(e as Map<String, dynamic>))
          .toList();
      return (data: data, totalCount: totalCount, pageCount: pageCount);
    } catch (e) {
      debugPrint('❌ fetchAll error: $e');
      rethrow;
    }
  }

  // ── Fetch total count for a single status ──────────────────────────────
  Future<int> fetchStatusCount(String status) async {
    try {
      final response = await get(
        '/api/admin/attractions?page=1&pageSize=1&status=$status',
      );
      final body = handleResponse(response);
      return (body['totalCount'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('❌ fetchStatusCount error: $e');
      return 0;
    }
  }

  // ── Fetch rows formatted for export ───────────────────────────────────────
  Future<List<AttractionExportRow>> fetchExportRows() async {
    try {
      final response = await get('/api/admin/attractions/export');
      final body = handleResponse(response);
      final list = body['data'] as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;

        final rawTypes = m['attraction_type'];
        final attractionTypes = rawTypes is List
            ? rawTypes
                .map((t) => _attractionTypeLabel(t.toString()))
                .join(', ')
            : '';

        return AttractionExportRow(
          attractionName: _val(m['attraction_name']),
          attractionTypes: attractionTypes.isEmpty ? '—' : attractionTypes,
          street: _val(m['street']),
          barangay: _val(m['barangay']),
          ownerName: _val(m['full_name']),
          phone: _val(m['phone']),
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ fetchExportRows error: $e');
      return [];
    }
  }

  // ── Fetch visitor rankings for a given month/year ─────────────────────────
  // Aggregation is done server-side; the Flutter side receives
  // pre-computed results.
  Future<List<AttractionRankingRow>> fetchRankings({
    required int month,
    required int year,
  }) async {
    try {
      final response = await get(
        '/api/admin/attractions/rankings?month=$month&year=$year',
      );
      final body = handleResponse(response);
      final list = body['data'] as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return AttractionRankingRow(
          attractionId: m['attraction_id'] as String,
          attractionName: m['attraction_name'] as String? ?? '—',
          totalVisitors: (m['total_visitors'] as num?)?.toInt() ?? 0,
          rank: (m['rank'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('❌ fetchRankings error: $e');
      rethrow;
    }
  }

  // ── Approve ───────────────────────────────────────────────────────────────
  Future<AttractionResult> approve(
    String attractionId, {
    String? remarks,
  }) async {
    try {
      final response = await put(
        '/api/admin/attractions/$attractionId/approve',
        {'remarks': remarks},
      );
      handleResponse(response);
      return AttractionResult.ok();
    } catch (e) {
      debugPrint('❌ approve error: $e');
      return AttractionResult.err('Failed to approve. Please try again.');
    }
  }

  // ── Reject ────────────────────────────────────────────────────────────────
  Future<AttractionResult> reject(
    String attractionId, {
    String? remarks,
  }) async {
    try {
      final response = await put(
        '/api/admin/attractions/$attractionId/reject',
        {'remarks': remarks},
      );
      handleResponse(response);
      return AttractionResult.ok();
    } catch (e) {
      debugPrint('❌ reject error: $e');
      return AttractionResult.err('Failed to reject. Please try again.');
    }
  }

  // ── Flag as warning ───────────────────────────────────────────────────────
  Future<AttractionResult> flag(
    String attractionId, {
    String? remarks,
  }) async {
    try {
      final response = await put(
        '/api/admin/attractions/$attractionId/flag',
        {'remarks': remarks},
      );
      handleResponse(response);
      return AttractionResult.ok();
    } catch (e) {
      debugPrint('❌ flag error: $e');
      return AttractionResult.err('Failed to flag. Please try again.');
    }
  }

  // ── Update status (manage: warning/approved) with message to owner ────────
  Future<AttractionResult> updateStatus(
    String attractionId,
    String newStatus, {
    required String reason,
    required String messageContent,
  }) async {
    try {
      final response = await put(
        '/api/admin/attractions/$attractionId/status',
        {
          'status': newStatus,
          'reason': reason,
          'messageContent': messageContent,
        },
      );
      handleResponse(response);
      return AttractionResult.ok();
    } catch (e) {
      debugPrint('❌ updateStatus error: $e');
      return AttractionResult.err('Failed to update status. Please try again.');
    }
  }

  // ── Soft delete ───────────────────────────────────────────────────────────
  // Named deleteAttraction to avoid conflict with BaseApi.delete()
  Future<AttractionResult> deleteAttraction(String attractionId) async {
    try {
      final response =
          await super.delete('/api/admin/attractions/$attractionId');
      handleResponse(response);
      return AttractionResult.ok();
    } catch (e) {
      debugPrint('❌ delete error: $e');
      return AttractionResult.err('Failed to delete. Please try again.');
    }
  }
}

// ─── Private helpers ──────────────────────────────────────────────────────────

/// Returns trimmed string or '—' if null/empty.
String _val(dynamic v) {
  final s = (v as String?)?.trim() ?? '';
  return s.isEmpty ? '—' : s;
}

/// Converts snake_case attraction type value to its display label.
String _attractionTypeLabel(String s) {
  switch (s) {
    case 'natural_attractions':
      return 'Natural Attractions';
    case 'cultural':
      return 'Cultural';
    case 'religious':
      return 'Religious';
    case 'historical_heritage_sites':
      return 'Historical Heritage Sites';
    case 'agri_tourism':
      return 'Agri-Tourism';
    case 'farm_tourism_sites':
      return 'Farm Tourism Sites';
    case 'ecotourism':
    default:
      return 'Ecotourism';
  }
}
