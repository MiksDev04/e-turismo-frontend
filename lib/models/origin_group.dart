class OriginGroup {
  const OriginGroup({
    this.id,
    this.country,
    this.nationality,
    this.isOverseas = false,
    this.province,
    this.cityMunicipality,
    this.maleCount = 0,
    this.femaleCount = 0,
  });

  final String? id;
  final String? country;
  final String? nationality; // 'Filipino' / 'Foreign' / null
  final bool isOverseas;
  final String? province; // Philippines only
  final String? cityMunicipality; // Philippines only
  final int maleCount;
  final int femaleCount;

  int get total => maleCount + femaleCount;
  bool get isDomestic => country?.toLowerCase() == 'philippines';

  /// True when the group carries origin information (an overseas flag or a
  /// selected country). Overseas groups have no country by design.
  bool get hasOrigin => isOverseas || (country?.trim().isNotEmpty ?? false);

  /// A group is only worth persisting/pushing when it has at least one guest
  /// AND an origin — matches the backend rule
  /// "Each origin group must have at least one guest (maleCount + femaleCount >= 1)".
  bool get isComplete => total > 0 && hasOrigin;

  /// Computed fallback when nationality is not stored.
  String get resolvedNationality =>
      nationality ?? (isDomestic || isOverseas ? 'Filipino' : 'Foreign');

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'country': isOverseas ? null : country,
      'nationality': nationality ?? resolvedNationality,
      'isOverseas': isOverseas,
      'province': (!isOverseas && isDomestic) ? province : null,
      'cityMunicipality': (!isOverseas && isDomestic) ? cityMunicipality : null,
      'maleCount': maleCount,
      'femaleCount': femaleCount,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory OriginGroup.fromJson(Map<String, dynamic> json) {
    final overseas = (json['isOverseas'] == true ||
        json['is_overseas'] == true ||
        json['is_overseas'] == 1);
    return OriginGroup(
      id: json['id']?.toString(),
      country: json['country']?.toString(),
      nationality: json['nationality']?.toString(),
      isOverseas: overseas,
      province: json['province']?.toString(),
      cityMunicipality:
          (json['cityMunicipality'] ?? json['city_municipality'])?.toString(),
      maleCount:
          (json['maleCount'] ?? json['male_count'] as num?)?.toInt() ?? 0,
      femaleCount:
          (json['femaleCount'] ?? json['female_count'] as num?)?.toInt() ?? 0,
    );
  }

  OriginGroup copyWith({
    String? id,
    String? country,
    String? nationality,
    bool? isOverseas,
    String? province,
    String? cityMunicipality,
    int? maleCount,
    int? femaleCount,
  }) {
    return OriginGroup(
      id: id ?? this.id,
      country: country ?? this.country,
      nationality: nationality ?? this.nationality,
      isOverseas: isOverseas ?? this.isOverseas,
      province: province ?? this.province,
      cityMunicipality: cityMunicipality ?? this.cityMunicipality,
      maleCount: maleCount ?? this.maleCount,
      femaleCount: femaleCount ?? this.femaleCount,
    );
  }
}
