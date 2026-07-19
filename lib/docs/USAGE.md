# PSGC Lookup — Flutter (Offline-First)

Region → Province → City/Municipality cascading picker, bundled locally so guest entry keeps working with no connection.

## 1. Get the data (one-time prep, not a runtime call)

- `GET https://psgc.gitlab.io/api/regions.json` → save as `assets/data/regions.json`
- For each region, `GET https://psgc.gitlab.io/api/regions/{regionCode}/provinces.json` → merge into one file keyed by region code:

```json
// assets/data/provinces_by_region.json
{
  "040000000": [ { "code": "042100000", "name": "Cavite", "regionCode": "040000000" }, ... ],
  "130000000": [ ... ]
}
```

- For each province, `GET https://psgc.gitlab.io/api/provinces/{provinceCode}/cities-municipalities.json` → merge into one file keyed by province code:

```json
// assets/data/cities_municipalities.json
{
  "042100000": [ { "code": "042114000", "name": "Dasmariñas", "isCapital": false }, ... ],
  "042117000": [ ... ]
}
```

A short one-off script (Dart or Node) can loop `regions.json`, then loop each region's provinces, hitting the endpoints above and writing the two merged files. Full dataset (17 regions, ~82 provinces, ~1,700 cities/municipalities) is still well under a few hundred KB — fine to bundle whole.

> **Heads up:** NCR (Metro Manila) has no provinces — its cities sit directly under districts instead. Its region code will come back with an empty province list. Decide during the fetch script whether to skip NCR, or treat its districts as a pseudo-province level, depending on whether your guest addresses need to cover it.

## 2. Register the assets

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/data/regions.json
    - assets/data/provinces_by_region.json
    - assets/data/cities_municipalities.json
```

## 3. Models

```dart
class Region {
  final String code;
  final String name;
  Region({required this.code, required this.name});
  factory Region.fromJson(Map<String, dynamic> j) => Region(code: j['code'], name: j['name']);
}

class Province {
  final String code;
  final String name;
  Province({required this.code, required this.name});
  factory Province.fromJson(Map<String, dynamic> j) => Province(code: j['code'], name: j['name']);
}

class CityMunicipality {
  final String code;
  final String name;
  final bool isCapital;
  CityMunicipality({required this.code, required this.name, required this.isCapital});
  factory CityMunicipality.fromJson(Map<String, dynamic> j) => CityMunicipality(
        code: j['code'],
        name: j['name'],
        isCapital: j['isCapital'] ?? false,
      );
}
```

## 4. Load into memory once (repository/singleton)

```dart
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class PsgcRepository {
  List<Region> _regions = [];
  Map<String, List<Province>> _provincesByRegion = {};
  Map<String, List<CityMunicipality>> _citiesByProvince = {};

  Future<void> load() async {
    final regionsRaw = await rootBundle.loadString('assets/data/regions.json');
    _regions = (jsonDecode(regionsRaw) as List)
        .map((e) => Region.fromJson(e))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final provincesRaw = await rootBundle.loadString('assets/data/provinces_by_region.json');
    final provincesDecoded = jsonDecode(provincesRaw) as Map<String, dynamic>;
    _provincesByRegion = provincesDecoded.map(
      (k, v) => MapEntry(
        k,
        (v as List).map((e) => Province.fromJson(e)).toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
      ),
    );

    final citiesRaw = await rootBundle.loadString('assets/data/cities_municipalities.json');
    final citiesDecoded = jsonDecode(citiesRaw) as Map<String, dynamic>;
    _citiesByProvince = citiesDecoded.map(
      (k, v) => MapEntry(
        k,
        (v as List).map((e) => CityMunicipality.fromJson(e)).toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
      ),
    );
  }

  List<Region> get regions => _regions;
  List<Province> provincesFor(String regionCode) => _provincesByRegion[regionCode] ?? [];
  List<CityMunicipality> citiesFor(String provinceCode) => _citiesByProvince[provinceCode] ?? [];
}
```

Load it once at app start (e.g. via a provider or singleton) so every screen reuses the same in-memory data instead of re-parsing JSON each time.

## 5. UI sketch (three cascading dropdowns)

```dart
DropdownButtonFormField<String>(
  decoration: const InputDecoration(labelText: 'Region'),
  items: repo.regions
      .map((r) => DropdownMenuItem(value: r.code, child: Text(r.name)))
      .toList(),
  onChanged: (code) => setState(() {
    selectedRegionCode = code;
    selectedProvinceCode = null;
    selectedCityCode = null;
  }),
),
if (selectedRegionCode != null)
  DropdownButtonFormField<String>(
    decoration: const InputDecoration(labelText: 'Province'),
    items: repo.provincesFor(selectedRegionCode!)
        .map((p) => DropdownMenuItem(value: p.code, child: Text(p.name)))
        .toList(),
    onChanged: (code) => setState(() {
      selectedProvinceCode = code;
      selectedCityCode = null;
    }),
  ),
if (selectedProvinceCode != null)
  DropdownButtonFormField<String>(
    decoration: const InputDecoration(labelText: 'City/Municipality'),
    items: repo.citiesFor(selectedProvinceCode!)
        .map((c) => DropdownMenuItem(value: c.code, child: Text(c.name)))
        .toList(),
    onChanged: (code) => setState(() => selectedCityCode = code),
  ),
```

## Notes

- Selecting a new region clears province and city below it; selecting a new province clears city — keeps the three dropdowns consistent.
- Same offline tradeoff as before: static reference data, no live API calls after the app is built. Re-run step 1 and rebundle to refresh the dataset later.
