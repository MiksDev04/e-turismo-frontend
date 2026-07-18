# PSGC Lookup — Flutter (Offline-First)

Province → cities/municipalities picker, bundled locally so guest entry keeps working with no connection.

## 1. Get the data (one-time prep, not a runtime call)

Pull the two shapes you need from the PSGC API and save them as local files:

- `GET https://psgc.gitlab.io/api/provinces.json` → save as `assets/data/provinces.json`
- For each province, `GET https://psgc.gitlab.io/api/provinces/{provinceCode}/cities-municipalities.json` → merge into one file keyed by province code:

```json
{
  "0128": [ { "code": "012801000", "name": "Alaminos", "isCapital": false }, ... ],
  "0129": [ ... ]
}
```

A short one-off script (Dart or Node) can loop `provinces.json` and write this merged file. Whole dataset is ~1,700 rows — small enough to bundle as-is.

## 2. Register the assets

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/data/provinces.json
    - assets/data/cities_municipalities.json
```

## 3. Models

```dart
class Province {
  final String code;
  final String name;
  Province({required this.code, required this.name});
  factory Province.fromJson(Map<String, dynamic> j) =>
      Province(code: j['code'], name: j['name']);
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
  List<Province> _provinces = [];
  Map<String, List<CityMunicipality>> _citiesByProvince = {};

  Future<void> load() async {
    final provincesRaw = await rootBundle.loadString('assets/data/provinces.json');
    _provinces = (jsonDecode(provincesRaw) as List)
        .map((e) => Province.fromJson(e))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final citiesRaw = await rootBundle.loadString('assets/data/cities_municipalities.json');
    final decoded = jsonDecode(citiesRaw) as Map<String, dynamic>;
    _citiesByProvince = decoded.map(
      (k, v) => MapEntry(k, (v as List).map((e) => CityMunicipality.fromJson(e)).toList()),
    );
  }

  List<Province> get provinces => _provinces;
  List<CityMunicipality> citiesFor(String provinceCode) =>
      _citiesByProvince[provinceCode] ?? [];
}
```

Load it once at app start (e.g. via a provider or singleton) so every screen reuses the same in-memory data instead of re-parsing JSON each time.

## 5. UI sketch

```dart
DropdownButtonFormField<String>(
  decoration: const InputDecoration(labelText: 'Province'),
  items: repo.provinces
      .map((p) => DropdownMenuItem(value: p.code, child: Text(p.name)))
      .toList(),
  onChanged: (code) => setState(() {
    selectedProvinceCode = code;
    selectedCityCode = null; // reset dependent field
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

- This is static reference data (PSA updates it infrequently) — no need to put it in your `sqflite` local DB unless you want it queryable alongside guest records. A plain JSON asset loaded once is simpler and plenty fast for ~1,700 rows.
- To refresh the dataset later, re-run step 1 and re-bundle — no code changes needed.
