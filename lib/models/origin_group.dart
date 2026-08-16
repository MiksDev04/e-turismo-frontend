class OriginGroup {
  const OriginGroup({
    this.id,
    this.country,
    this.isOverseas = false,
    this.province,
    this.cityMunicipality,
    this.maleCount = 0,
    this.femaleCount = 0,
  });

  final String? id;
  final String? country; // null when isOverseas
  final bool isOverseas;
  final String? province; // Philippines only
  final String? cityMunicipality; // Philippines only
  final int maleCount;
  final int femaleCount;

  int get total => maleCount + femaleCount;
  bool get isDomestic => country?.toLowerCase() == 'philippines';
  String get nationality => isDomestic ? 'Filipino' : 'Foreign';

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'country': isOverseas ? null : country,
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
    bool? isOverseas,
    String? province,
    String? cityMunicipality,
    int? maleCount,
    int? femaleCount,
  }) {
    return OriginGroup(
      id: id ?? this.id,
      country: country ?? this.country,
      isOverseas: isOverseas ?? this.isOverseas,
      province: province ?? this.province,
      cityMunicipality: cityMunicipality ?? this.cityMunicipality,
      maleCount: maleCount ?? this.maleCount,
      femaleCount: femaleCount ?? this.femaleCount,
    );
  }
}
