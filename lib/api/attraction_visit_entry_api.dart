import 'package:flutter/foundation.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'base_api.dart';

class VisitEntryResult {
  final bool success;
  final String? error;

  const VisitEntryResult._({
    required this.success,
    this.error,
  });

  factory VisitEntryResult.ok() => const VisitEntryResult._(success: true);

  factory VisitEntryResult.err(String error) =>
      VisitEntryResult._(success: false, error: error);
}

class VisitEntryData {
  const VisitEntryData({
    required this.visitDate,
    required this.guestCount,
    required this.isForeign,
    this.country,
    this.province,
    this.cityMunicipality,
    this.maleCount,
    this.femaleCount,
  });

  final DateTime visitDate;
  final int guestCount;
  final bool isForeign;
  final String? country;
  final String? province;
  final String? cityMunicipality;
  final int? maleCount;
  final int? femaleCount;

  Map<String, dynamic> toJson() {
    final visitDateStr =
        "${visitDate.year.toString().padLeft(4, '0')}-"
        "${visitDate.month.toString().padLeft(2, '0')}-"
        "${visitDate.day.toString().padLeft(2, '0')}";

    var male = maleCount ?? 0;
    var female = femaleCount ?? 0;
    if (male == 0 && female == 0) {
      male = (guestCount * 0.471).round();
      female = guestCount - male;
    } else if (male == 0) {
      male = guestCount - female;
    } else if (female == 0) {
      female = guestCount - male;
    }

    return {
      'visitDate': visitDateStr,
      'guestCount': guestCount,
      'isForeign': isForeign,
      'country': country,
      'province': province,
      'cityMunicipality': cityMunicipality,
      'maleCount': male,
      'femaleCount': female,
    };
  }
}

class AttractionVisitEntryApi extends BaseApi {
  AttractionVisitEntryApi();

  Future<String?> resolveAttractionId() async {
    final session =
        SessionService.instance.current ??
        await SessionService.instance.loadAndCache();
    return session?.attractionId;
  }

  Future<VisitEntryResult> saveVisitEntry(VisitEntryData data) async {
    if (!ConnectivityService.instance.isOnline || !hasToken) {
      return VisitEntryResult.err(
        'Attraction accounts are online-only. Please connect to the internet.',
      );
    }

    try {
      final attractionId = await resolveAttractionId();
      if (attractionId == null || attractionId.isEmpty) {
        return VisitEntryResult.err(
          'No attraction account associated with this user.',
        );
      }

      final payload = data.toJson()..['attractionId'] = attractionId;

      final response = await post(
        '/api/attraction/visit-entry/visit-entries',
        payload,
      );

      handleResponse(response);
      return VisitEntryResult.ok();
    } on ApiException catch (e) {
      debugPrint('saveVisitEntry: API error ${e.statusCode} - ${e.message}');
      if (e.statusCode == 401) {
        return VisitEntryResult.err('Session expired. Please log in again.');
      }
      return VisitEntryResult.err(e.message);
    } catch (e) {
      debugPrint('saveVisitEntry: unexpected error - $e');
      return VisitEntryResult.err(
        'Failed to save visit entry. Please try again.',
      );
    }
  }
}
