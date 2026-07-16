// lib/ui/admin/models/accommodation_models.dart

import 'package:app/core/enums/business_enums.dart';

enum AccommodationStatus { approved, pending, rejected, warning }

class Accommodation {
  const Accommodation({
    required this.id,
    required this.profileId,
    required this.name,
    required this.tradeName,
    required this.businessType,
    required this.businessLines,
    required this.owner,
    required this.email,
    required this.contact,
    required this.rooms,
    required this.status,
    required this.address,
    required this.street,
    required this.barangay,
    required this.cityMunicipality,
    required this.province,
    required this.region,
    required this.dotAccreditationClassification,
    required this.aeIdCodeLgu,
    required this.permitNumber,
    required this.registrationNumber,
    required this.permitFileUrl,
    required this.validIdUrl,
    this.remarks,
    this.createdAt,
  });

  final String id;
  final String profileId;
  final String name;
  final String tradeName;
  final BusinessType businessType;
  final List<BusinessLine> businessLines;
  final String owner;
  final String? email;
  final String contact;
  final int rooms;
  final AccommodationStatus status;
  final String address;
  // Structured address + DOT fields (database updated)
  final String street;
  final String barangay;
  final String cityMunicipality;
  final String province;
  final String region;
  final String dotAccreditationClassification;
  final String aeIdCodeLgu;
  final String permitNumber;
  final String registrationNumber;
  final String permitFileUrl;
  final String validIdUrl;
  final String? remarks;
  final String? createdAt;

  static AccommodationStatus _parseStatus(String s) {
    switch (s) {
      case 'approved':
        return AccommodationStatus.approved;
      case 'rejected':
        return AccommodationStatus.rejected;
      case 'warning':
        return AccommodationStatus.warning;
      default:
        return AccommodationStatus.pending;
    }
  }

  static BusinessType _parseBusinessType(String value) {
    switch (value) {
      case 'corporation':
        return BusinessType.corporation;
      case 'partnership':
        return BusinessType.partnership;
      default:
        return BusinessType.soleProprietorship;
    }
  }

  static BusinessLine _parseBusinessLine(String value) {
    switch (value) {
      case 'hotel':
        return BusinessLine.hotel;
      case 'resort':
        return BusinessLine.resort;
      case 'motel':
        return BusinessLine.motel;
      case 'pension_inn':
        return BusinessLine.pensionInn;
      case 'youth_hostel':
        return BusinessLine.youthHostel;
      case 'apartment':
        return BusinessLine.apartment;
      default:
        return BusinessLine.others;
    }
  }

  static String _combineOwnerName(Map<String, dynamic> map) {
    final ownerParts = <String>[
      map['owner_first_name'] as String? ?? '',
      map['owner_middle_name'] as String? ?? '',
      map['owner_last_name'] as String? ?? '',
    ].where((part) => part.trim().isNotEmpty).toList();

    if (ownerParts.isNotEmpty) {
      return ownerParts.join(' ').trim();
    }

    final profile = map['profiles'] as Map<String, dynamic>?;
    final profileName = profile?['full_name'] as String?;
    if (profileName != null && profileName.trim().isNotEmpty) {
      return profileName.trim();
    }

    return '—';
  }

  factory Accommodation.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    final rawLines = map['business_line'];
    final businessLines = rawLines is List
        ? rawLines.whereType<String>().map(_parseBusinessLine).toList()
        : const <BusinessLine>[];

    return Accommodation(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      name: map['business_name'] as String,
      tradeName: map['tradename'] as String? ?? '—',
      businessType: _parseBusinessType(map['business_type'] as String),
      businessLines: businessLines,
      owner: _combineOwnerName(map),
      email: profile?['email'] as String? ?? '—', // We'll fetch this on demand in the details modal
      contact: profile?['phone'] as String? ?? '—',
      rooms: map['total_rooms'] as int,
      status: _parseStatus(map['status'] as String),
      // Prefer new `street` column, fall back to legacy `address` if present
      address: (map['street'] as String?)?.isNotEmpty == true
          ? (map['street'] as String)
          : (map['address'] as String? ?? '—'),
      street: map['street'] as String? ?? (map['address'] as String? ?? '—'),
      barangay: map['barangay'] as String? ?? '—',
      cityMunicipality: map['city_municipality'] as String? ?? '—',
      province: map['province'] as String? ?? '—',
      region: map['region'] as String? ?? '—',
      dotAccreditationClassification: map['dot_accreditation_classification'] as String? ?? '—',
      aeIdCodeLgu: map['ae_id_code_lgu'] as String? ?? map['ae_id_code'] as String? ?? '—',
      permitNumber: map['permit_number'] as String? ?? '—',
      registrationNumber: map['registration_number'] as String? ?? '—',
      permitFileUrl: map['permit_file_url'] as String? ?? '',
      validIdUrl: map['valid_id_url'] as String? ?? '',
      remarks: map['remarks'] as String?,
      createdAt: map['created_at'] as String?,
    );
  }

  Accommodation copyWith({AccommodationStatus? status, String? remarks}) {
    return Accommodation(
      id: id,
      profileId: profileId,
      name: name,
      tradeName: tradeName,
      businessType: businessType,
      businessLines: businessLines,
      owner: owner,
      email: email,
      contact: contact,
      rooms: rooms,
      status: status ?? this.status,
      address: address,
      street: street,
      barangay: barangay,
      cityMunicipality: cityMunicipality,
      province: province,
      region: region,
      dotAccreditationClassification: dotAccreditationClassification,
      aeIdCodeLgu: aeIdCodeLgu,
      permitNumber: permitNumber,
      registrationNumber: registrationNumber,
      permitFileUrl: permitFileUrl,
      validIdUrl: validIdUrl,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt,
    );
  }

  String get businessLineLabel =>
      businessLines.isEmpty ? '—' : businessLines.map((line) => line.label).join(', ');
}

// ─── Room Info ────────────────────────────────────────────────────────────────

class RoomInfo {
  const RoomInfo({
    required this.roomNumber,
    required this.occupancy,
    required this.roomStatus,
  });

  final String roomNumber;
  final int occupancy;
  final String roomStatus;

  factory RoomInfo.fromMap(Map<String, dynamic> map) {
    return RoomInfo(
      roomNumber: map['room_number'] as String? ?? '—',
      occupancy: (map['occupancy'] as num?)?.toInt() ?? 1,
      roomStatus: (map['room_status'] as String?) ?? 'vacant',
    );
  }
}
