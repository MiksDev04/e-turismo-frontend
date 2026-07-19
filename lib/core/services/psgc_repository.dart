import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/psgc_models.dart';

class PsgcRepository {
  PsgcRepository._internal();
  static final PsgcRepository instance = PsgcRepository._internal();

  List<Region> _regions = [];
  Map<String, List<Province>> _provincesByRegion = {};
  Map<String, List<CityMunicipality>> _citiesByProvince = {};

  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;

    try {
      final regionsRaw =
          await rootBundle.loadString('assets/data/regions.json');
      _regions = (jsonDecode(regionsRaw) as List)
          .map((e) => Region.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final provincesRaw = await rootBundle
          .loadString('assets/data/provinces_by_region.json');
      final provincesDecoded =
          jsonDecode(provincesRaw) as Map<String, dynamic>;
      _provincesByRegion = provincesDecoded.map(
        (k, v) => MapEntry(
          k,
          (v as List)
              .map((e) => Province.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name)),
        ),
      );

      final citiesRaw = await rootBundle
          .loadString('assets/data/cities_municipalities.json');
      final citiesDecoded =
          jsonDecode(citiesRaw) as Map<String, dynamic>;
      _citiesByProvince = citiesDecoded.map(
        (k, v) => MapEntry(
          k,
          (v as List)
              .map((e) =>
                  CityMunicipality.fromJson(e as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name)),
        ),
      );

      _loaded = true;
    } catch (e) {
      debugPrint('⚠️ PsgcRepository.load failed: $e');
    }
  }

  List<Region> get regions => _regions;

  List<Province> provincesFor(String regionCode) =>
      _provincesByRegion[regionCode] ?? [];

  List<CityMunicipality> citiesFor(String provinceCode) =>
      _citiesByProvince[provinceCode] ?? [];

  List<CityMunicipality> citiesForRegion(String regionCode) =>
      _citiesByProvince[regionCode] ?? [];

  String? findRegionCodeByName(String name) {
    for (final r in _regions) {
      if (r.name == name) return r.code;
    }
    return null;
  }

  String? findProvinceCodeByName(String regionCode, String name) {
    final provinces = _provincesByRegion[regionCode];
    if (provinces == null) return null;
    final normalised = name.trim().toLowerCase();
    for (final p in provinces) {
      final pName = p.name.trim().toLowerCase();
      if (pName == normalised) return p.code;
    }
    // Fallback: try with "City of" prefix
    for (final p in provinces) {
      final pName = 'City of ${p.name}'.trim().toLowerCase();
      if (pName == normalised) return p.code;
    }
    return null;
  }

  String? findCityCodeByName(String provinceCode, String name,
      {String? regionCode}) {
    // Try province lookup first
    final cities = _citiesByProvince[provinceCode];
    if (cities != null) {
      final result = _findCityInList(cities, name);
      if (result != null) return result;
    }
    // Fallback to region lookup (for regions without provinces like NCR)
    if (regionCode != null) {
      final regionCities = _citiesByProvince[regionCode];
      if (regionCities != null) {
        return _findCityInList(regionCities, name);
      }
    }
    return null;
  }

  String? _findCityInList(List<CityMunicipality> cities, String name) {
    final normalised = name.trim().toLowerCase();
    for (final c in cities) {
      final cName = c.name.trim().toLowerCase();
      if (cName == normalised) return c.code;
    }
    for (final c in cities) {
      final cName = 'City of ${c.name}'.trim().toLowerCase();
      if (cName == normalised) return c.code;
    }
    final stripped = normalised.replaceFirst('City of ', '');
    for (final c in cities) {
      final cName = c.name.trim().toLowerCase();
      if (cName == stripped) return c.code;
    }
    return null;
  }
}
