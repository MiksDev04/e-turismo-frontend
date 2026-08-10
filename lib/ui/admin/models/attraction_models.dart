// lib/ui/admin/models/attraction_models.dart

enum AttractionStatus { approved, pending, rejected, warning }

enum AttractionType {
  ecotourism,
  naturalAttractions,
  cultural,
  religious,
  historicalHeritageSites,
  agriTourism,
  farmTourismSites;
}

extension AttractionTypeLabel on AttractionType {
  String get label => switch (this) {
        AttractionType.ecotourism => 'Ecotourism',
        AttractionType.naturalAttractions => 'Natural Attractions',
        AttractionType.cultural => 'Cultural',
        AttractionType.religious => 'Religious',
        AttractionType.historicalHeritageSites => 'Historical Heritage Sites',
        AttractionType.agriTourism => 'Agri-Tourism',
        AttractionType.farmTourismSites => 'Farm Tourism Sites',
      };
}

class Attraction {
  const Attraction({
    required this.id,
    required this.profileId,
    required this.name,
    required this.attractionTypes,
    required this.owner,
    required this.email,
    required this.contact,
    required this.status,
    required this.address,
    required this.street,
    required this.barangay,
    required this.validIdUrl,
    this.remarks,
    this.createdAt,
  });

  final String id;
  final String profileId;
  final String name;
  final List<AttractionType> attractionTypes;
  final String owner;
  final String? email;
  final String contact;
  final AttractionStatus status;
  final String address;
  final String street;
  final String barangay;
  final String validIdUrl;
  final String? remarks;
  final String? createdAt;

  static AttractionStatus _parseStatus(String s) {
    switch (s) {
      case 'approved':
        return AttractionStatus.approved;
      case 'rejected':
        return AttractionStatus.rejected;
      case 'warning':
        return AttractionStatus.warning;
      default:
        return AttractionStatus.pending;
    }
  }

  static AttractionType _parseType(String value) {
    switch (value) {
      case 'natural_attractions':
        return AttractionType.naturalAttractions;
      case 'cultural':
        return AttractionType.cultural;
      case 'religious':
        return AttractionType.religious;
      case 'historical_heritage_sites':
        return AttractionType.historicalHeritageSites;
      case 'agri_tourism':
        return AttractionType.agriTourism;
      case 'farm_tourism_sites':
        return AttractionType.farmTourismSites;
      default:
        return AttractionType.ecotourism;
    }
  }

  factory Attraction.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    final rawTypes = map['attraction_type'];
    final attractionTypes = rawTypes is List
        ? rawTypes.whereType<String>().map(_parseType).toList()
        : const <AttractionType>[];

    return Attraction(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      name: map['attraction_name'] as String,
      attractionTypes: attractionTypes,
      owner: profile?['full_name'] as String? ?? '—',
      email: profile?['email'] as String? ?? '—',
      contact: profile?['phone'] as String? ?? '—',
      status: _parseStatus(map['status'] as String),
      address: (map['street'] as String?)?.isNotEmpty == true
          ? (map['street'] as String)
          : '—',
      street: map['street'] as String? ?? '—',
      barangay: map['barangay'] as String? ?? '—',
      validIdUrl: map['valid_id_url'] as String? ?? '',
      remarks: map['remarks'] as String?,
      createdAt: map['created_at'] as String?,
    );
  }

  Attraction copyWith({AttractionStatus? status, String? remarks}) {
    return Attraction(
      id: id,
      profileId: profileId,
      name: name,
      attractionTypes: attractionTypes,
      owner: owner,
      email: email,
      contact: contact,
      status: status ?? this.status,
      address: address,
      street: street,
      barangay: barangay,
      validIdUrl: validIdUrl,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt,
    );
  }

  String get attractionTypeLabel => attractionTypes.isEmpty
      ? '—'
      : attractionTypes.map((t) => t.label).join(', ');
}
