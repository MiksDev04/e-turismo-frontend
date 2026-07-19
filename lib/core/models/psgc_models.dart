class Region {
  final String code;
  final String name;
  const Region({required this.code, required this.name});
  factory Region.fromJson(Map<String, dynamic> j) =>
      Region(code: j['code'] as String, name: j['name'] as String);
}

class Province {
  final String code;
  final String name;
  const Province({required this.code, required this.name});
  factory Province.fromJson(Map<String, dynamic> j) =>
      Province(code: j['code'] as String, name: j['name'] as String);
}

class CityMunicipality {
  final String code;
  final String name;
  final bool isCapital;
  const CityMunicipality({
    required this.code,
    required this.name,
    required this.isCapital,
  });
  factory CityMunicipality.fromJson(Map<String, dynamic> j) =>
      CityMunicipality(
        code: j['code'] as String,
        name: j['name'] as String,
        isCapital: j['isCapital'] as bool? ?? false,
      );
}
