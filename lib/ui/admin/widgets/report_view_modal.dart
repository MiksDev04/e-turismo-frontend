import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/core/services/connectivity_service.dart';
import 'package:app/api/admin_report_api.dart';
import 'package:printing/printing.dart';

// ─────────────────────────────────────────────────────────────────────────
// DAE-1B TEMPLATE PALETTE
// Colors / font lifted directly from ON_Blank_Form.xlsx (all 3 sheets share
// this palette): light-yellow column headers, blue category/region bands,
// cyan sub-totals, green totals, yellow grand-total, Arial throughout.
// ─────────────────────────────────────────────────────────────────────────
class _Dae {
  static const String font = 'Arial';
  static const String dayFont = 'Bell MT';
  static const Color paper = Colors.white;
  static const Color ink = Colors.black;
  static const Color gridLine = Colors.black;
  static const Color headerYellow = Color(0xFFFFFF66);
  static const Color categoryBlue = Color(0xFF0070C0);
  static const Color subtotalCyan = Color(0xFF00B0F0);
  static const Color totalGreen = Color(0xFF92D050);
  static const Color grandTotalYellow = Color(0xFFFFFF00);
  static const double dataSize = 8.0;
  static const double headerSize = 10.0;
  static const double titleSize = 12.0;
  static const double indicatorSize = 9.0;
}

// ─────────────────────────────────────────────────────────────────────────
// VAR REPORT PALETTE  (lifted from VAR-REPORT.xlsx)
// Yellow header (#FFFF00), green total (#92D050), Arial throughout.
// ─────────────────────────────────────────────────────────────────────────
class _Var {
  static const String font = 'Arial';
  static const Color paper = Colors.white;
  static const Color ink = Colors.black;
  static const Color gridLine = Colors.black;
  static const Color headerYellow = Color(0xFFFFFF00);
  static const Color totalGreen = Color(0xFF92D050);
  static const Color emailBlue = Color(0xFF0000FF);
  static const double dataSize = 8.0;
  static const double headerSize = 9.0;
  static const double smallSize = 9.0;

  static const double nameColWidth = 260;
  static const double attrCodeWidth = 70;
  static const double dataColWidth = 55;
  static const int kDataRowCount = 41;
}

// ─────────────────────────────────────────────────────────────────────────
// VAR 1 (TOURIST ATTRACTION) PALETTE
// Lifted from same day blank.xlsx: yellow header (#FFFF00), green total
// (#92D050), Arial Narrow table cells, Arial titles.  Day column = B, a
// "Week Day" column = C, then 15 data columns (D..R) with per-column widths
// and a mixed thin/medium border scheme at the group boundaries.
// ─────────────────────────────────────────────────────────────────────────
class _Var1 {
  static const String font = 'Arial';
  static const String narrow = 'Arial Narrow';
  static const String dayFont = 'Calibri';
  static const Color paper = Colors.white;
  static const Color ink = Colors.black;
  static const Color gridLine = Colors.black;
  static const Color headerYellow = Color(0xFFFFFF00);
  static const Color totalGreen = Color(0xFF92D050);
  static const Color grandTotalYellow = Color(0xFFFFFF00);

  static const double dataSize = 10.0; // Arial Narrow 10 data cells
  static const double daySize = 11.0; // Calibri 11 day / weekday cells
  static const double headerSize = 8.0; // Arial Narrow 8 bold headers

  static const double thin = 0.5;
  static const double medium = 0.5;

  // Column widths (px) for B..R from the template (52 / 74 / 15 data cols).
  static const double dayColWidth = 52;
  static const double weekdayColWidth = 74;
  static const List<double> dataColWidths = [
    66, 69, 70, 66, 68, 70, 66, 64, 66, 70, 64, 64, 73, 77, 80,
  ];
  static double get dataColWidthSum =>
      dataColWidths.fold(0, (a, b) => a + b);
  static double get tableWidth =>
      dayColWidth + weekdayColWidth + dataColWidthSum;

  // Row heights (px) for the 4-level header and data rows.
  static const double headerRow1 = 22; // 16.5pt
  static const double headerRow2 = 20; // 15pt
  static const double headerRow3 = 38; // 28.5pt
  static const double headerRow4 = 23; // 17.25pt
  static const double dataRowHeight = 32; // 24pt
  static const double lastDataRowHeight = 35; // 26.25pt
  static const double totalRowHeight = 47; // 35.25pt
}

// ─────────────────────────────────────────────────────────────────────────
// ATTRACTION TYPE LABELS
// Values stored in tourist_attractions.attraction_type (snake_case) mapped to
// the display labels used on the VAR 1 form.
// ─────────────────────────────────────────────────────────────────────────
const Map<String, String> _kAttractionTypeLabels = {
  'ecotourism': 'Ecotourism',
  'natural_attractions': 'Natural Attractions',
  'cultural': 'Cultural',
  'religious': 'Religious',
  'historical_heritage_sites': 'Historical Heritage Sites',
  'agri_tourism': 'Agri-Tourism',
  'farm_tourism_sites': 'Farm Tourism Sites',
};

String _attractionTypeLabel(String value) {
  final key = value.trim();
  if (key.isEmpty) return '';
  final known = _kAttractionTypeLabels[key];
  if (known != null) return known;
  return key
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

// Week Day (Mon-Sun) short names indexed by DateTime.weekday (1=Mon .. 7=Sun).
const List<String> _kWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _weekdayLabel(int year, int month, int day) {
  final wd = DateTime(year, month, day).weekday;
  return _kWeekdayShort[wd - 1];
}

// ─────────────────────────────────────────────────────────────────────────
// ROW MODEL
// One definition list drives all three variants (daily / summary / series).
// Each row knows how to pull its own value out of a MonthData snapshot for
// a given "day" key — callers just decide which (MonthData, day) pairs to
// treat as columns.
// ─────────────────────────────────────────────────────────────────────────
enum _RKind {
  topCategory, // e.g. "PHILIPPINE RESIDENTS", "ASIA"          -> blue
  subCategory, // e.g. "ASEAN"                                  -> blue, italic
  valueCategory, // e.g. "NON-PHILIPPINE RESIDENCES"            -> blue, italic, has value
  dataLeaf, // e.g. "BRUNEI", "FILIPINO NATIONALITY"            -> white, italic
  subtotal, // "SUB-TOTAL"                                      -> cyan
  total, // "TOTAL PHILIPPINE RESIDENTS"                        -> green
  grandTotal, // "GRAND TOTAL GUEST ARRIVALS"                   -> yellow
  sectionTitle, // "PART II.  Other Indicators"                 -> white, large bold
  subsectionTitle, // "A. DAE2:", "B. VOLUME PER SEX"            -> yellow, bold
  plainNote, // "Alternative Submission"                        -> white, bold italic
  indicator, // "1. Rooms Occupied", "a. Philippine Residents"  -> white
  indicatorBold, // "1. Male", "2. Female"                      -> white, bold
  footnote, // asterisk note                                    -> white, small italic
  spacer, // blank divider row
}

typedef _Getter =
    num Function(EstablishmentReport est, MonthData md, String day);

class _RRow {
  final String label;
  final _RKind kind;
  final int indent;
  final _Getter? value;
  final String Function(num value)? format;

  _RRow(this.label, this.kind, {this.indent = 0, this.value, this.format});
}

// ─────────────────────────────────────────────────────────────────────────
// COUNTRY LISTS (exact order/grouping as the "COUNTRY OF RESIDENCE" column)
// ─────────────────────────────────────────────────────────────────────────
const List<String> _kAsean = [
  'BRUNEI',
  'CAMBODIA',
  'INDONESIA',
  'LAOS',
  'MALAYSIA',
  'MYANMAR',
  'SINGAPORE',
  'THAILAND',
  'VIETNAM',
];
const List<String> _kEastAsia = [
  'CHINA',
  'HONGKONG',
  'JAPAN',
  'KOREA',
  'TAIWAN',
];
const List<String> _kSouthAsia = [
  'BANGLADESH',
  'INDIA',
  'IRAN',
  'NEPAL',
  'PAKISTAN',
  'SRI LANKA',
];
const List<String> _kMiddleEast = [
  'BAHRAIN',
  'EGYPT',
  'ISRAEL',
  'JORDAN',
  'KUWAIT',
  'SAUDI ARABIA',
  'UNITED ARAB EMIRATES',
];
const List<String> _kNorthAmerica = ['CANADA', 'MEXICO', 'USA'];
const List<String> _kSouthAmerica = [
  'ARGENTINA',
  'BRAZIL',
  'COLOMBIA',
  'PERU',
  'VENEZUELA',
];
const List<String> _kWesternEurope = [
  'AUSTRIA',
  'BELGIUM',
  'FRANCE',
  'GERMANY',
  'LUXEMBOURG',
  'NETHERLANDS',
  'SWITZERLAND',
];
const List<String> _kNorthernEurope = [
  'DENMARK',
  'FINLAND',
  'IRELAND',
  'NORWAY',
  'SWEDEN',
  'UNITED KINGDOM',
];
const List<String> _kSouthernEurope = [
  'GREECE',
  'ITALY',
  'PORTUGAL',
  'SPAIN',
  'UNION OF SERBIA AND MONTENEGRO',
];
const List<String> _kEasternEurope = [
  'COMMONWEALTH OF INDEPENDENT STATES',
  'POLAND',
  'RUSSIA',
];
const List<String> _kAustralasia = [
  'AUSTRALIA',
  'GUAM',
  'NAURU',
  'NEW ZEALAND',
  'PAPUA NEW GUINEA',
];
const List<String> _kAfrica = ['NIGERIA', 'SOUTH AFRICA'];

const List<String> _kAllCountries = [
  ..._kAsean,
  ..._kEastAsia,
  ..._kSouthAsia,
  ..._kMiddleEast,
  ..._kNorthAmerica,
  ..._kSouthAmerica,
  ..._kWesternEurope,
  ..._kNorthernEurope,
  ..._kSouthernEurope,
  ..._kEasternEurope,
  ..._kAustralasia,
  ..._kAfrica,
];

// ─────────────────────────────────────────────────────────────────────────
// VALUE HELPERS
// day == '0' is treated as "the aggregate for this snapshot" (matches the
// convention already used elsewhere in this app for residentsByDay/'0').
// ─────────────────────────────────────────────────────────────────────────
int _res(MonthData md, String day, String key) =>
    md.residentsByDay?[day]?[key] ?? 0;

String _titleCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
    .join(' ');

int _country(MonthData md, String day, String name) {
  final byCountry = md.countryByDay;
  if (byCountry == null) return 0;
  final dayMap =
      byCountry[name] ??
      byCountry[name.toUpperCase()] ??
      byCountry[_titleCase(name)];
  return dayMap?[day] ?? 0;
}

int _sumCountries(MonthData md, String day, List<String> names) =>
    names.fold<int>(0, (sum, n) => sum + _country(md, day, n));

int _totalPh(EstablishmentReport est, MonthData md, String day) =>
    _res(md, day, 'philippine_resident_filipino') +
    _res(md, day, 'philippine_resident_foreign');

// The full country breakdown IS the "listed" foreign-resident total.
int _listedForeign(EstablishmentReport est, MonthData md, String day) =>
    _sumCountries(md, day, _kAllCountries);

int _unlistedForeign(EstablishmentReport est, MonthData md, String day) =>
    _res(md, day, 'unlisted_foreign_resident');

int _totalNonPh(EstablishmentReport est, MonthData md, String day) =>
    _listedForeign(est, md, day) + _unlistedForeign(est, md, day);

int _overseasFil(EstablishmentReport est, MonthData md, String day) =>
    _res(md, day, 'overseas_filipino');

int _unspecifiedGuest(EstablishmentReport est, MonthData md, String day) =>
    _res(md, day, 'unspecified_guest');

int _grandTotal(EstablishmentReport est, MonthData md, String day) =>
    _totalPh(est, md, day) +
    _totalNonPh(est, md, day) +
    _overseasFil(est, md, day) +
    _unspecifiedGuest(est, md, day);

int _roomsOccupied(EstablishmentReport est, MonthData md, String day) =>
    day == '0' ? md.totalRoomsOccupied : (md.roomsOccupied?[day] ?? 0);

// Rooms available = totalRooms − roomsOccupied that day.
// For the aggregate (day '0'), multiply totalRooms by daysInMonth then
// subtract total rooms occupied for the month.
int _roomsAvailable(EstablishmentReport est, MonthData md, String day) {
  final occupied = _roomsOccupied(est, md, day);
  if (day == '0') {
    final year = md.year ?? 2025;
    final daysInMonth = DateTime(year, md.month + 1, 0).day;
    return est.totalRooms * daysInMonth - occupied;
  }
  return est.totalRooms - occupied;
}

int _guestNights(EstablishmentReport est, MonthData md, String day) =>
    day == '0' ? (md.guestNights ?? 0) : (md.guestNightsByDay?[day] ?? 0);

int _sexCategory(MonthData md, String day, String sex, String category) =>
    md.sexByDay?[day]?[sex]?[category] ?? 0;

int _maleTotal(EstablishmentReport est, MonthData md, String day) =>
    _sexCategory(md, day, 'male', 'philippine_resident_filipino') +
    _sexCategory(md, day, 'male', 'philippine_resident_foreign') +
    _sexCategory(md, day, 'male', 'listed_foreign_resident') +
    _sexCategory(md, day, 'male', 'unlisted_foreign_resident') +
    _sexCategory(md, day, 'male', 'overseas_filipino') +
    _sexCategory(md, day, 'male', 'unspecified_guest');

int _femaleTotal(EstablishmentReport est, MonthData md, String day) =>
    _sexCategory(md, day, 'female', 'philippine_resident_filipino') +
    _sexCategory(md, day, 'female', 'philippine_resident_foreign') +
    _sexCategory(md, day, 'female', 'listed_foreign_resident') +
    _sexCategory(md, day, 'female', 'unlisted_foreign_resident') +
    _sexCategory(md, day, 'female', 'overseas_filipino') +
    _sexCategory(md, day, 'female', 'unspecified_guest');

// ─────────────────────────────────────────────────────────────────────────
// ROW LIST — mirrors "COUNTRY OF RESIDENCE" rows 25-149, then Part II
// rows 151-175 of the template, in exact order.
// ─────────────────────────────────────────────────────────────────────────
List<_RRow> _regionBlock(
  String name,
  List<String> countries, {
  bool asTopCategory = false,
}) {
  return [
    _RRow(
      name,
      asTopCategory ? _RKind.topCategory : _RKind.subCategory,
      indent: asTopCategory ? 0 : 1,
    ),
    ...countries.map(
      (c) => _RRow(
        c,
        _RKind.dataLeaf,
        indent: 2,
        value: (est, md, day) => _country(md, day, c),
      ),
    ),
    _RRow(
      'SUB-TOTAL',
      _RKind.subtotal,
      indent: 2,
      value: (est, md, day) => _sumCountries(md, day, countries),
    ),
    _RRow('', _RKind.spacer),
  ];
}

List<_RRow> _buildHierarchyRows() {
  return [
    _RRow('PHILIPPINE RESIDENTS', _RKind.topCategory),
    _RRow(
      'FILIPINO NATIONALITY',
      _RKind.dataLeaf,
      indent: 1,
      value: (est, md, day) => _res(md, day, 'philippine_resident_filipino'),
    ),
    _RRow(
      'FOREIGN NATIONALITY',
      _RKind.dataLeaf,
      indent: 1,
      value: (est, md, day) => _res(md, day, 'philippine_resident_foreign'),
    ),
    _RRow('TOTAL PHILIPPINE RESIDENTS', _RKind.total, value: _totalPh),
    _RRow('', _RKind.spacer),
    _RRow('NON-PHILIPPINE RESIDENTS', _RKind.topCategory),
    _RRow('', _RKind.spacer),
    _RRow('ASIA', _RKind.topCategory),
    ..._regionBlock('ASEAN', _kAsean),
    ..._regionBlock('EAST ASIA', _kEastAsia),
    ..._regionBlock('SOUTH ASIA', _kSouthAsia),
    ..._regionBlock('MIDDLE EAST', _kMiddleEast),
    _RRow('AMERICA', _RKind.topCategory),
    ..._regionBlock('NORTH AMERICA', _kNorthAmerica),
    ..._regionBlock('SOUTH AMERICA', _kSouthAmerica),
    _RRow('EUROPE', _RKind.topCategory),
    ..._regionBlock('WESTERN EUROPE', _kWesternEurope),
    ..._regionBlock('NORTHERN EUROPE', _kNorthernEurope),
    ..._regionBlock('SOUTHERN EUROPE', _kSouthernEurope),
    ..._regionBlock('EASTERN EUROPE', _kEasternEurope),
    ..._regionBlock('AUSTRALASIA/PACIFIC', _kAustralasia, asTopCategory: true),
    ..._regionBlock('AFRICA', _kAfrica, asTopCategory: true),
    _RRow('OTHERS AND UNSPECIFIED', _RKind.topCategory),
    _RRow(
      'NON-PHILIPPINE RESIDENCES',
      _RKind.valueCategory,
      value: _unlistedForeign,
    ),
    _RRow('', _RKind.spacer),
    _RRow('TOTAL NON-PHILIPPINE RESIDENTS', _RKind.total, value: _totalNonPh),
    _RRow('', _RKind.spacer),
    _RRow('OVERSEAS FILIPINOS*', _RKind.valueCategory, value: _overseasFil),
    _RRow('', _RKind.spacer),
    _RRow('GRAND TOTAL GUEST ARRIVALS', _RKind.grandTotal, value: _grandTotal),
    _RRow(
      'Total Philippine Residents',
      _RKind.total,
      indent: 1,
      value: _totalPh,
    ),
    _RRow(
      'Total Non-Philippine Residents',
      _RKind.total,
      indent: 1,
      value: _totalNonPh,
    ),
    _RRow(
      'Total Overseas Filipinos',
      _RKind.total,
      indent: 1,
      value: _overseasFil,
    ),
    _RRow(
      'Total Guest with Unspecified Residence',
      _RKind.total,
      indent: 1,
      value: _unspecifiedGuest,
    ),
  ];
}

List<_RRow> _buildIndicatorRows() {
  return [
    _RRow('', _RKind.spacer),
    _RRow('PART II.  Other Indicators', _RKind.sectionTitle),
    _RRow('', _RKind.spacer),
    _RRow('A. DAE2:', _RKind.subsectionTitle),
    _RRow('1. Rooms Occupied', _RKind.indicator, value: _roomsOccupied),
    _RRow(
      '2. Rooms available for the month',
      _RKind.indicator,
      value: _roomsAvailable,
    ),
    _RRow('3. Total Guest nights', _RKind.indicator, value: _guestNights),
    _RRow('Alternative Submission', _RKind.plainNote),
    _RRow(
      '1. Average Monthly Occupancy Rate',
      _RKind.indicator,
      value: (est, md, day) => 0,
    ),
    _RRow(
      '2. Average Length of Stay (in Nights)',
      _RKind.indicator,
      value: (est, md, day) => 0,
    ),
    _RRow('B. VOLUME PER SEX', _RKind.subsectionTitle),
    _RRow('1. Male', _RKind.indicatorBold),
    _RRow(
      'a. Philippine Residents',
      _RKind.indicator,
      indent: 1,
      value: (est, md, day) =>
          _sexCategory(md, day, 'male', 'philippine_resident_filipino') +
          _sexCategory(md, day, 'male', 'philippine_resident_foreign'),
    ),
    _RRow(
      'b. Non-Philippine/Foreign Residents (including unspecified)',
      _RKind.indicator,
      indent: 1,
      value: (est, md, day) =>
          _sexCategory(md, day, 'male', 'listed_foreign_resident') +
          _sexCategory(md, day, 'male', 'unlisted_foreign_resident') +
          _sexCategory(md, day, 'male', 'unspecified_guest'),
    ),
    _RRow(
      'c. Overseas Filipinos',
      _RKind.indicator,
      indent: 1,
      value: (est, md, day) =>
          _sexCategory(md, day, 'male', 'overseas_filipino'),
    ),
    _RRow(
      'd. Others/Unspecified Guest',
      _RKind.indicator,
      indent: 1,
      value: (est, md, day) =>
          _sexCategory(md, day, 'male', 'unlisted_foreign_resident') +
          _sexCategory(md, day, 'male', 'unspecified_guest'),
    ),
    _RRow('x. Total', _RKind.indicator, indent: 1, value: _maleTotal),
    _RRow('2. Female', _RKind.indicatorBold),
    _RRow(
      'a. Philippine Residents',
      _RKind.indicator,
      indent: 1,
      value: (est, md, day) =>
          _sexCategory(md, day, 'female', 'philippine_resident_filipino') +
          _sexCategory(md, day, 'female', 'philippine_resident_foreign'),
    ),
    _RRow(
      'b. Non-Philippine/Foreign Residents (including unspecified)',
      _RKind.indicator,
      indent: 1,
      value: (est, md, day) =>
          _sexCategory(md, day, 'female', 'listed_foreign_resident') +
          _sexCategory(md, day, 'female', 'unlisted_foreign_resident') +
          _sexCategory(md, day, 'female', 'unspecified_guest'),
    ),
    _RRow(
      'c. Overseas Filipinos',
      _RKind.indicator,
      indent: 1,
      value: (est, md, day) =>
          _sexCategory(md, day, 'female', 'overseas_filipino'),
    ),
    _RRow(
      'd. Others/Unspecified Guest',
      _RKind.indicator,
      indent: 1,
      value: (est, md, day) =>
          _sexCategory(md, day, 'female', 'unlisted_foreign_resident') +
          _sexCategory(md, day, 'female', 'unspecified_guest'),
    ),
    _RRow('x. Total', _RKind.indicator, indent: 1, value: _femaleTotal),
    _RRow('', _RKind.spacer),
    _RRow(
      '* Philippine passport holders permanently residing abroad; excludes overseas Filipino workers and Former Filipinos',
      _RKind.footnote,
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────
// ROW STYLING
// ─────────────────────────────────────────────────────────────────────────
Color _bgFor(_RKind k) {
  switch (k) {
    case _RKind.topCategory:
    case _RKind.subCategory:
    case _RKind.valueCategory:
      return _Dae.categoryBlue;
    case _RKind.subtotal:
      return _Dae.subtotalCyan;
    case _RKind.total:
      return _Dae.totalGreen;
    case _RKind.grandTotal:
    case _RKind.subsectionTitle:
      return _Dae.grandTotalYellow;
    default:
      return _Dae.paper;
  }
}

TextStyle _styleFor(_RKind k) {
  const base = TextStyle(
    fontFamily: _Dae.font,
    color: _Dae.ink,
    fontSize: _Dae.dataSize,
  );
  switch (k) {
    case _RKind.topCategory:
      return base.copyWith(fontWeight: FontWeight.bold);
    case _RKind.subCategory:
    case _RKind.valueCategory:
    case _RKind.dataLeaf:
    case _RKind.subtotal:
      return base.copyWith(
        fontWeight: FontWeight.bold,
        fontStyle: FontStyle.italic,
      );
    case _RKind.total:
    case _RKind.grandTotal:
      return base.copyWith(fontWeight: FontWeight.bold);
    case _RKind.sectionTitle:
      return base.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: _Dae.titleSize,
      );
    case _RKind.subsectionTitle:
      return base.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: _Dae.titleSize,
      );
    case _RKind.plainNote:
      return base.copyWith(
        fontWeight: FontWeight.bold,
        fontStyle: FontStyle.italic,
        fontSize: _Dae.titleSize,
      );
    case _RKind.indicator:
      return base.copyWith(fontSize: _Dae.indicatorSize);
    case _RKind.indicatorBold:
      return base.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: _Dae.indicatorSize,
      );
    case _RKind.footnote:
      return base.copyWith(
        fontSize: _Dae.indicatorSize,
        fontStyle: FontStyle.italic,
        color: Colors.black54,
      );
    default:
      return base;
  }
}

// Zero / missing data renders blank, matching the source template's blank
// cells rather than a distracting wall of zeroes.
String _fmt(_RRow r, num v) {
  if (r.value == null) return '';
  if (v == 0) return '';
  return r.format != null ? r.format!(v) : '${v.round()}';
}

// ─────────────────────────────────────────────────────────────────────────
// COLUMN WIDTHS  (from ON Blank Form.xlsx, day 1 widened +20%)
// Col A (labels) = 320 px,  Cols B-AF (days 1-31) = 41 px each,
// Col AG (TOTAL) = 102 px (original).
// ─────────────────────────────────────────────────────────────────────────
const double _labelColWidth = 320;
const double _dayColWidth = 41;
const double _totalColWidth = 102;
const double _dataRowHeight = 20;
const double _headerRowHeight = 22;
const double _spacerRowHeight = 8;

// ─────────────────────────────────────────────────────────────────────────
// COLUMN SPEC + TABLE WIDGET
// ─────────────────────────────────────────────────────────────────────────
class _ColumnSpec {
  final String label;
  final MonthData md;
  final String day;
  const _ColumnSpec(this.label, this.md, this.day);
}

class _ReportTable extends StatelessWidget {
  const _ReportTable({
    required this.est,
    required this.columns,
    required this.showTotalColumn,
    this.labelColWidth,
    this.dataColWidth,
    this.totalColWidth,
  });

  final EstablishmentReport est;
  final List<_ColumnSpec> columns;
  final bool showTotalColumn;
  final double? labelColWidth;
  final double? dataColWidth;
  final double? totalColWidth;

  @override
  Widget build(BuildContext context) {
    final rows = [..._buildHierarchyRows(), ..._buildIndicatorRows()];

    final effectiveLabelWidth = labelColWidth ?? _labelColWidth;
    final effectiveDataWidth = dataColWidth ?? _dayColWidth;
    final effectiveTotalWidth = totalColWidth ?? _totalColWidth;

    final columnWidths = <int, TableColumnWidth>{
      0: FixedColumnWidth(effectiveLabelWidth),
    };
    for (int i = 0; i < columns.length; i++) {
      columnWidths[i + 1] = FixedColumnWidth(effectiveDataWidth);
    }
    if (showTotalColumn) {
      columnWidths[columns.length + 1] = FixedColumnWidth(effectiveTotalWidth);
    }

    final tableRows = <TableRow>[];
    tableRows.add(_buildHeaderRow());
    for (final r in rows) {
      tableRows.add(_buildDataRow(r));
    }

    return Table(
      columnWidths: columnWidths,
      border: TableBorder.all(color: _Dae.gridLine, width: 0.5),
      children: tableRows,
    );
  }

  TableRow _buildHeaderRow() {
    final cells = <TableCell>[
      _cell(
        'COUNTRY OF RESIDENCE',
        TextStyle(
          fontFamily: _Dae.font,
          fontWeight: FontWeight.bold,
          color: _Dae.ink,
          fontSize: _Dae.dataSize,
        ),
        _Dae.headerYellow,
        height: _headerRowHeight,
        alignLeft: true,
      ),
    ];
    for (final c in columns) {
      cells.add(
        _cell(
          c.label,
          TextStyle(
            fontFamily: _Dae.dayFont,
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
            color: _Dae.ink,
            fontSize: _Dae.dataSize,
          ),
          _Dae.headerYellow,
          height: _headerRowHeight,
        ),
      );
    }
    if (showTotalColumn) {
      cells.add(
        _cell(
          'TOTAL',
          TextStyle(
            fontFamily: _Dae.font,
            fontWeight: FontWeight.bold,
            color: _Dae.ink,
            fontSize: _Dae.dataSize,
          ),
          _Dae.headerYellow,
          height: _headerRowHeight,
        ),
      );
    }
    return TableRow(children: cells);
  }

  TableRow _buildDataRow(_RRow r) {
    if (r.kind == _RKind.spacer) {
      final colCount = 1 + columns.length + (showTotalColumn ? 1 : 0);
      return TableRow(
        children: List.generate(
          colCount,
          (_) => TableCell(child: SizedBox(height: _spacerRowHeight)),
        ),
      );
    }

    final style = _styleFor(r.kind);
    final bg = _bgFor(r.kind);

    final cells = <TableCell>[
      _cell(
        r.label,
        style,
        bg,
        height: _dataRowHeight,
        alignLeft: true,
        indent: r.indent,
      ),
    ];

    num rowTotal = 0;
    final isTotalRow =
        r.kind == _RKind.subtotal ||
        r.kind == _RKind.total ||
        r.kind == _RKind.grandTotal;
    final forceZeroData = isTotalRow || !showTotalColumn;
    for (final c in columns) {
      final v = r.value?.call(est, c.md, c.day) ?? 0;
      rowTotal += v;
      final text = (forceZeroData && v == 0 && r.value != null)
          ? '0'
          : _fmt(r, v);
      cells.add(_cell(text, style, bg, height: _dataRowHeight));
    }

    if (showTotalColumn) {
      final totalText = (rowTotal == 0 && r.value != null)
          ? '0'
          : _fmt(r, rowTotal);
      cells.add(
        _cell(
          totalText,
          style.copyWith(fontWeight: FontWeight.bold),
          bg,
          height: _dataRowHeight,
        ),
      );
    }

    return TableRow(children: cells);
  }

  static TableCell _cell(
    String text,
    TextStyle style,
    Color bg, {
    double height = 20,
    bool alignLeft = false,
    int indent = 0,
  }) {
    return TableCell(
      child: Container(
        height: height,
        color: bg,
        padding: alignLeft
            ? EdgeInsets.only(left: 4 + indent * 14.0)
            : const EdgeInsets.only(right: 4),
        alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
        child: Text(text, style: style, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// VAR REPORT TABLE  (mirrors VAR-REPORT.xlsx exactly)
// 4-level merged header, 41 data rows, green total row.
// ─────────────────────────────────────────────────────────────────────────
Container _varDataCell(
  String text, {
  required double width,
  Color bg = _Var.paper,
  bool bold = false,
  double height = 17,
  bool isTotal = false,
}) {
  final effectiveBg = isTotal ? _Var.totalGreen : bg;
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: effectiveBg,
      border: Border.all(color: _Var.gridLine, width: 0.5),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: _Var.font,
        fontSize: _Var.dataSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: _Var.ink,
      ),
    ),
  );
}

Container _varHeaderCell(
  String text, {
  required double width,
  bool bold = false,
  bool wrap = false,
  Color bg = _Var.headerYellow,
  double height = 20,
  TextAlign textAlign = TextAlign.center,
}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: bg,
      border: Border.all(color: _Var.gridLine, width: 0.5),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
    child: Text(
      text,
      textAlign: textAlign,
      softWrap: wrap,
      overflow: TextOverflow.clip,
      style: TextStyle(
        fontFamily: _Var.font,
        fontSize: _Var.headerSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: _Var.ink,
      ),
    ),
  );
}

// Column widths for the VAR table
const double _varNameW = _Var.nameColWidth;
const double _varAttrW = _Var.attrCodeWidth;
const double _varDataW = _Var.dataColWidth;

class _VarReportTable extends StatelessWidget {
  const _VarReportTable({required this.establishments, required this.totals});

  final List<EstablishmentReport> establishments;
  final VarData totals;

  static const double _hRowH = 20.0;
  static const double _hTotalW = _varNameW + _varAttrW + 15 * _varDataW;
  static const double _hTotalH = _hRowH * 4;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_buildHeader(), _buildDataSection()],
    );
  }

  Widget _buildHeader() {
    // Column x-positions
    const double xName = 0;
    const double xAttr = _varNameW;
    const double xData = _varNameW + _varAttrW;
    // Row y-positions
    const double y0 = 0;
    const double y1 = _hRowH;
    const double y2 = _hRowH * 2;
    const double y3 = _hRowH * 3;

    Widget cell(
      String text, {
      required double x,
      required double y,
      required double w,
      required double h,
      bool bold = true,
      bool wrap = false,
      TextAlign align = TextAlign.center,
    }) {
      return Positioned(
        left: x,
        top: y,
        width: w,
        height: h,
        child: _varHeaderCell(
          text,
          width: w,
          bold: bold,
          wrap: wrap,
          height: h,
          textAlign: align,
        ),
      );
    }

    return SizedBox(
      width: _hTotalW,
      height: _hTotalH,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // ── Row 1 (y=0) ──────────────────────────────────────────────
          // B12:C12 = "Visitor Attraction"
          cell(
            'Visitor Attraction',
            x: xName,
            y: y0,
            w: _varNameW + _varAttrW,
            h: _hRowH,
          ),
          // D12:O12 = "*** Place of Residence"
          cell(
            '*** Place of Residence',
            x: xData,
            y: y0,
            w: _varDataW * 12,
            h: _hRowH,
          ),
          // P12:R14 = "* Grand Total Number of Visitors" (spans 3 rows)
          cell(
            '* Grand Total\nNumber of\nVisitors',
            x: xData + _varDataW * 12,
            y: y0,
            w: _varDataW * 3,
            h: _hRowH * 3,
            wrap: true,
          ),

          // ── Row 2 (y=20) ────────────────────────────────────────────
          // B13:B15 = "Name" (spans 3 rows)
          cell(
            'Name',
            x: xName,
            y: y1,
            w: _varNameW,
            h: _hRowH * 3,
            wrap: true,
          ),
          // C13:C15 = "Attraction Code" (spans 3 rows)
          cell(
            'Attraction\nCode',
            x: xAttr,
            y: y1,
            w: _varAttrW,
            h: _hRowH * 3,
            wrap: true,
          ),
          // D13:L13 = "Philippines"
          cell('Philippines', x: xData, y: y1, w: _varDataW * 9, h: _hRowH),
          // M13:O14 = "Foreign Country Residence" (spans 2 rows)
          cell(
            'Foreign Country\nResidence',
            x: xData + _varDataW * 9,
            y: y1,
            w: _varDataW * 3,
            h: _hRowH * 2,
            wrap: true,
          ),

          // ── Row 3 (y=40) ────────────────────────────────────────────
          // D14:F14 = "This City/Municipality"
          cell(
            'This City/Municipality',
            x: xData,
            y: y2,
            w: _varDataW * 3,
            h: _hRowH,
            wrap: true,
          ),
          // G14:I14 = "Other City/Municipality"
          cell(
            'Other City/Municipality',
            x: xData + _varDataW * 3,
            y: y2,
            w: _varDataW * 3,
            h: _hRowH,
            wrap: true,
          ),
          // J14:L14 = "Other Province"
          cell(
            'Other Province',
            x: xData + _varDataW * 6,
            y: y2,
            w: _varDataW * 3,
            h: _hRowH,
            wrap: true,
          ),

          // ── Row 4 (y=60) – M / F / T for each group ─────────────────
          for (int g = 0; g < 5; g++) ...[
            cell(
              'Male',
              x: xData + _varDataW * (g * 3),
              y: y3,
              w: _varDataW,
              h: _hRowH,
              bold: true,
            ),
            cell(
              'Female',
              x: xData + _varDataW * (g * 3 + 1),
              y: y3,
              w: _varDataW,
              h: _hRowH,
              bold: true,
            ),
            cell(
              'Total',
              x: xData + _varDataW * (g * 3 + 2),
              y: y3,
              w: _varDataW,
              h: _hRowH,
              bold: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDataSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < _Var.kDataRowCount; i++) _buildDataRow(i),
        _buildTotalRow(),
      ],
    );
  }

  Row _buildDataRow(int index) {
    final est = index < establishments.length ? establishments[index] : null;
    final vd = est?.varData;

    String cell(int val) => val == 0 ? '' : '$val';
    String cellTotal(int val) => '$val';

    final name = est?.businessName ?? '';
    final totalMale =
        (vd?.maleThisCity ?? 0) +
        (vd?.maleOtherCity ?? 0) +
        (vd?.maleOtherProvince ?? 0) +
        (vd?.maleForeign ?? 0);
    final totalFemale =
        (vd?.femaleThisCity ?? 0) +
        (vd?.femaleOtherCity ?? 0) +
        (vd?.femaleOtherProvince ?? 0) +
        (vd?.femaleForeign ?? 0);
    final grandTotal = totalMale + totalFemale;

    return Row(
      children: [
        _varDataCell(name, width: _varNameW),
        _varDataCell(
          (est?.businessLine?.isNotEmpty ?? false) ? '9-902' : '',
          width: _varAttrW,
        ),
        _varDataCell(cell(vd?.maleThisCity ?? 0), width: _varDataW),
        _varDataCell(cell(vd?.femaleThisCity ?? 0), width: _varDataW),
        _varDataCell(cellTotal((vd?.totalThisCity ?? 0)), width: _varDataW),
        _varDataCell(cell(vd?.maleOtherCity ?? 0), width: _varDataW),
        _varDataCell(cell(vd?.femaleOtherCity ?? 0), width: _varDataW),
        _varDataCell(cellTotal((vd?.totalOtherCity ?? 0)), width: _varDataW),
        _varDataCell(cell(vd?.maleOtherProvince ?? 0), width: _varDataW),
        _varDataCell(cell(vd?.femaleOtherProvince ?? 0), width: _varDataW),
        _varDataCell(
          cellTotal((vd?.totalOtherProvince ?? 0)),
          width: _varDataW,
        ),
        _varDataCell(cell(vd?.maleForeign ?? 0), width: _varDataW),
        _varDataCell(cell(vd?.femaleForeign ?? 0), width: _varDataW),
        _varDataCell(cellTotal((vd?.totalForeign ?? 0)), width: _varDataW),
        _varDataCell(cell(totalMale), width: _varDataW),
        _varDataCell(cell(totalFemale), width: _varDataW),
        _varDataCell(cellTotal(grandTotal), width: _varDataW),
      ],
    );
  }

  Row _buildTotalRow() {
    String v(int val) => '$val';
    final grandMale = totals.grandMale;
    final grandFemale = totals.grandFemale;
    final grandTotal = totals.grandTotal;

    return Row(
      children: [
        _varDataCell(
          'Total of this Month ****',
          width: _varNameW,
          bold: true,
          isTotal: true,
        ),
        _varDataCell('', width: _varAttrW, isTotal: true),
        _varDataCell(v(totals.maleThisCity), width: _varDataW, isTotal: true),
        _varDataCell(v(totals.femaleThisCity), width: _varDataW, isTotal: true),
        _varDataCell(v(totals.totalThisCity), width: _varDataW, isTotal: true),
        _varDataCell(v(totals.maleOtherCity), width: _varDataW, isTotal: true),
        _varDataCell(
          v(totals.femaleOtherCity),
          width: _varDataW,
          isTotal: true,
        ),
        _varDataCell(v(totals.totalOtherCity), width: _varDataW, isTotal: true),
        _varDataCell(
          v(totals.maleOtherProvince),
          width: _varDataW,
          isTotal: true,
        ),
        _varDataCell(
          v(totals.femaleOtherProvince),
          width: _varDataW,
          isTotal: true,
        ),
        _varDataCell(
          v(totals.totalOtherProvince),
          width: _varDataW,
          isTotal: true,
        ),
        _varDataCell(v(totals.maleForeign), width: _varDataW, isTotal: true),
        _varDataCell(v(totals.femaleForeign), width: _varDataW, isTotal: true),
        _varDataCell(v(totals.totalForeign), width: _varDataW, isTotal: true),
        _varDataCell(v(grandMale), width: _varDataW, isTotal: true),
        _varDataCell(v(grandFemale), width: _varDataW, isTotal: true),
        _varDataCell(v(grandTotal), width: _varDataW, isTotal: true),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// VAR 1 (TOURIST ATTRACTION) REPORT TABLE
// Mirrors VAR-REPORT-ATTRACTION_DAILY.xlsx rows 16-51: 4-level yellow
// header, 31 day rows, green total row.
// ─────────────────────────────────────────────────────────────────────────
Container _var1DataCell(
  String text, {
  required double width,
  double height = _Var1.dataRowHeight,
  bool bold = false,
  bool isTotal = false,
  bool isGrandTotal = false,
  bool day = false,
  double? fontSize,
  double? borderLeft,
  double? borderRight,
  double? borderTop,
  double? borderBottom,
}) {
  final double l = borderLeft ?? _Var1.thin;
  final double r = borderRight ?? _Var1.thin;
  final double t = borderTop ?? _Var1.thin;
  final double b = borderBottom ?? _Var1.thin;
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: isGrandTotal
          ? _Var1.grandTotalYellow
          : isTotal
              ? _Var1.totalGreen
              : _Var1.paper,
      border: Border(
        left: BorderSide(color: _Var1.gridLine, width: l),
        right: BorderSide(color: _Var1.gridLine, width: r),
        top: BorderSide(color: _Var1.gridLine, width: t),
        bottom: BorderSide(color: _Var1.gridLine, width: b),
      ),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: day ? _Var1.dayFont : _Var1.narrow,
        fontSize: fontSize ??
            (isTotal
                ? (isGrandTotal ? 12.0 : 11.0)
                : day
                    ? _Var1.daySize
                    : _Var1.dataSize),
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: _Var1.ink,
      ),
    ),
  );
}

Container _var1HeaderCell(
  String text, {
  required double width,
  bool bold = true,
  bool wrap = false,
  double height = _Var1.headerRow1,
  double? fontSize,
  double? borderLeft,
  double? borderRight,
  double? borderTop,
  double? borderBottom,
}) {
  final double l = borderLeft ?? _Var1.thin;
  final double r = borderRight ?? _Var1.thin;
  final double t = borderTop ?? _Var1.thin;
  final double b = borderBottom ?? _Var1.thin;
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _Var1.headerYellow,
      border: Border(
        left: BorderSide(color: _Var1.gridLine, width: l),
        right: BorderSide(color: _Var1.gridLine, width: r),
        top: BorderSide(color: _Var1.gridLine, width: t),
        bottom: BorderSide(color: _Var1.gridLine, width: b),
      ),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
    child: Text(
      text,
      textAlign: TextAlign.center,
      softWrap: wrap,
      overflow: TextOverflow.clip,
      style: TextStyle(
        fontFamily: _Var1.narrow,
        fontSize: fontSize ?? _Var1.headerSize,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        color: _Var1.ink,
      ),
    ),
  );
}

class _Var1ReportTable extends StatelessWidget {
  const _Var1ReportTable({
    required this.establishment,
    required this.month,
    required this.year,
  });

  final EstablishmentReport establishment;
  final int month;
  final int year;

  // Column widths (px) for B..R in order.
  static const List<double> _colW = [
    _Var1.dayColWidth,
    _Var1.weekdayColWidth,
    ..._Var1.dataColWidths,
  ];

  static const double _dayW = _Var1.dayColWidth;
  static const double _wdW = _Var1.weekdayColWidth;

  static const double _h1 = _Var1.headerRow1;
  static const double _h2 = _Var1.headerRow2;
  static const double _h3 = _Var1.headerRow3;
  static const double _h4 = _Var1.headerRow4;
  static const double _headerH = _h1 + _h2 + _h3 + _h4;

  static double get _tableW => _Var1.tableWidth;

  static double _colX(int index) => _colW.take(index).fold(0.0, (a, b) => a + b);

  // Medium vertical separators: outer edges plus the group boundaries
  // (C|D, F|G, I|J, L|M, O|P) and the Grand Total block (P|Q, Q|R).
  static bool _mediumLeft(int col) =>
      col == 0 ||
      col == 2 ||
      col == 5 ||
      col == 8 ||
      col == 11 ||
      col == 14 ||
      col == 15 ||
      col == 16;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_buildHeader(), _buildDataSection()],
    );
  }

  Widget _buildHeader() {
    final double xData = _colX(2);
    const double y0 = 0;
    const double y1 = _h1;
    const double y2 = _h1 + _h2;
    const double y3 = _h1 + _h2 + _h3;

    Widget cell(
      String text, {
      required double x,
      required double y,
      required double w,
      required double h,
      bool wrap = false,
      double? fontSize,
      double? borderLeft,
      double? borderRight,
      double? borderTop,
      double? borderBottom,
    }) {
      return Positioned(
        left: x,
        top: y,
        width: w,
        height: h,
        child: _var1HeaderCell(
          text,
          width: w,
          height: h,
          wrap: wrap,
          fontSize: fontSize,
          borderLeft: borderLeft,
          borderRight: borderRight,
          borderTop: borderTop,
          borderBottom: borderBottom,
        ),
      );
    }

    const labels = ['Male', 'Female', 'Total'];

    return SizedBox(
      width: _tableW,
      height: _headerH,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // ── Row 1: "Date" (B:C), "*** Place of Residence" (D:O),
          //    "* Grand Total Number of Visitors" (P:R, 3 rows) ────────
          cell(
            'Date',
            x: 0,
            y: y0,
            w: _dayW + _wdW,
            h: _h1,
            borderLeft: _Var1.medium,
            borderTop: _Var1.medium,
          ),
          cell(
            '*** Place of Residence',
            x: xData,
            y: y0,
            w: _colX(14) - xData,
            h: _h1,
            borderLeft: _Var1.medium,
            borderTop: _Var1.medium,
          ),
          cell(
            '* Grand Total Number of Visitors',
            x: _colX(14),
            y: y0,
            w: _colW[14] + _colW[15] + _colW[16],
            h: _h1 + _h2 + _h3,
            wrap: true,
            borderLeft: _Var1.medium,
            borderRight: _Var1.medium,
            borderTop: _Var1.medium,
          ),

          // ── Row 2 ────────────────────────────────────────────────────
          cell(
            'Day',
            x: 0,
            y: y1,
            w: _dayW,
            h: _h2 + _h3 + _h4,
            wrap: true,
            borderLeft: _Var1.medium,
            borderBottom: _Var1.medium,
          ),
          cell(
            'Week Day (Mon-Sun)',
            x: _dayW,
            y: y1,
            w: _wdW,
            h: _h2 + _h3 + _h4,
            wrap: true,
            borderBottom: _Var1.medium,
          ),
          cell(
            'Philippines',
            x: xData,
            y: y1,
            w: _colX(11) - xData,
            h: _h2,
            borderLeft: _Var1.medium,
          ),
          cell(
            'Foreign Country Residence',
            x: _colX(11),
            y: y1,
            w: _colX(14) - _colX(11),
            h: _h2 + _h3,
            wrap: true,
            borderLeft: _Var1.medium,
          ),

          // ── Row 3 ────────────────────────────────────────────────────
          cell(
            'This City/Municipality',
            x: xData,
            y: y2,
            w: _colX(5) - xData,
            h: _h3,
            wrap: true,
            borderLeft: _Var1.medium,
          ),
          cell(
            'Other City/Municipality',
            x: _colX(5),
            y: y2,
            w: _colX(8) - _colX(5),
            h: _h3,
            wrap: true,
            borderLeft: _Var1.medium,
          ),
          cell(
            'Other Province',
            x: _colX(8),
            y: y2,
            w: _colX(11) - _colX(8),
            h: _h3,
            wrap: true,
            borderLeft: _Var1.medium,
          ),

          // ── Row 4: M / F / T for each of the 5 groups ────────────────
          for (int g = 0; g < 5; g++)
            for (int j = 0; j < 3; j++) ...[
              cell(
                labels[j],
                x: _colX(2 + g * 3 + j),
                y: y3,
                w: _colW[2 + g * 3 + j],
                h: _h4,
                borderLeft:
                    _mediumLeft(2 + g * 3 + j) ? _Var1.medium : null,
                borderRight: (2 + g * 3 + j) == 16 ? _Var1.medium : null,
                borderBottom: _Var1.medium,
              ),
            ],
        ],
      ),
    );
  }

  Widget _buildDataSection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int day = 1; day <= 31; day++) _buildDayRow(day),
        _buildTotalRow(),
      ],
    );
  }

  Row _buildDayRow(int day) {
    final vd = establishment.attractionDaily?['$day'];
    final m = vd ?? const VarData();
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final isInMonth = day <= daysInMonth;
    final isLast = day == 31;
    final height =
        isLast ? _Var1.lastDataRowHeight : _Var1.dataRowHeight;

    String v(int val) => val == 0 ? '' : '$val';

    final values = <String>[
      isInMonth ? '$day' : '',
      isInMonth ? _weekdayLabel(year, month, day) : '',
      v(m.maleThisCity),
      v(m.femaleThisCity),
      m.totalThisCity == 0 ? '' : '${m.totalThisCity}',
      v(m.maleOtherCity),
      v(m.femaleOtherCity),
      m.totalOtherCity == 0 ? '' : '${m.totalOtherCity}',
      v(m.maleOtherProvince),
      v(m.femaleOtherProvince),
      m.totalOtherProvince == 0 ? '' : '${m.totalOtherProvince}',
      v(m.maleForeign),
      v(m.femaleForeign),
      m.totalForeign == 0 ? '' : '${m.totalForeign}',
      v(m.grandMale),
      v(m.grandFemale),
      m.grandTotal == 0 ? '' : '${m.grandTotal}',
    ];

    return Row(
      children: [
        for (int col = 0; col < 17; col++)
          _var1DataCell(
            values[col],
            width: _colW[col],
            height: height,
            day: col < 2,
            borderLeft: _mediumLeft(col) ? _Var1.medium : null,
            borderRight: col == 16 ? _Var1.medium : null,
          ),
      ],
    );
  }

  Row _buildTotalRow() {
    final t = establishment.attractionTotals ?? const VarData();
    String v(int x) => '$x';

    final values = <String>[
      v(t.maleThisCity),
      v(t.femaleThisCity),
      v(t.totalThisCity),
      v(t.maleOtherCity),
      v(t.femaleOtherCity),
      v(t.totalOtherCity),
      v(t.maleOtherProvince),
      v(t.femaleOtherProvince),
      v(t.totalOtherProvince),
      v(t.maleForeign),
      v(t.femaleForeign),
      v(t.totalForeign),
      v(t.grandMale),
      v(t.grandFemale),
      v(t.grandTotal),
    ];

    return Row(
      children: [
        _var1DataCell(
          'Total of this Month ****',
          width: _dayW + _wdW,
          height: _Var1.totalRowHeight,
          bold: true,
          fontSize: 10,
          isTotal: true,
          borderLeft: _Var1.medium,
          borderBottom: _Var1.medium,
        ),
        for (int i = 0; i < 15; i++)
          _var1DataCell(
            values[i],
            width: _Var1.dataColWidths[i],
            height: _Var1.totalRowHeight,
            bold: true,
            isTotal: i < 14,
            isGrandTotal: i == 14,
            borderLeft: _Var1.medium,
            borderRight: i == 14 ? _Var1.medium : null,
            borderBottom: _Var1.medium,
          ),
      ],
    );
  }
}

// ─── Per-tab establishment view with own scroll controllers ──────────────────
class _EstablishmentView extends StatefulWidget {
  const _EstablishmentView({
    required this.content,
    required this.tableWidth,
    required this.zoomLevel,
    required this.onZoomChanged,
  });

  final Widget content;
  final double tableWidth;
  final double zoomLevel;
  final void Function(double) onZoomChanged;

  @override
  State<_EstablishmentView> createState() => _EstablishmentViewState();
}

class _EstablishmentViewState extends State<_EstablishmentView> {
  final GlobalKey _contentKey = GlobalKey();
  final ScrollController _hScrollCtrl = ScrollController();
  final ScrollController _hScrollCtrlBottom = ScrollController();
  final ScrollController _vScrollCtrl = ScrollController();
  bool _syncingScroll = false;
  double _unscaledContentHeight = 0;

  void _syncFromContent() {
    if (_syncingScroll) return;
    _syncingScroll = true;
    if (_hScrollCtrlBottom.hasClients &&
        _hScrollCtrlBottom.offset != _hScrollCtrl.offset) {
      _hScrollCtrlBottom.jumpTo(_hScrollCtrl.offset);
    }
    _syncingScroll = false;
  }

  void _syncFromBottom() {
    if (_syncingScroll) return;
    _syncingScroll = true;
    if (_hScrollCtrl.hasClients &&
        _hScrollCtrl.offset != _hScrollCtrlBottom.offset) {
      _hScrollCtrl.jumpTo(_hScrollCtrlBottom.offset);
    }
    _syncingScroll = false;
  }

  void _measureContent() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final contentBox =
          _contentKey.currentContext?.findRenderObject() as RenderBox?;
      if (contentBox != null) {
        final h = contentBox.size.height;
        if (h > 0 && (h - _unscaledContentHeight).abs() > 0.5) {
          setState(() => _unscaledContentHeight = h);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _hScrollCtrl.addListener(_syncFromContent);
    _hScrollCtrlBottom.addListener(_syncFromBottom);
    _measureContent();
  }

  @override
  void dispose() {
    _hScrollCtrl.removeListener(_syncFromContent);
    _hScrollCtrlBottom.removeListener(_syncFromBottom);
    _hScrollCtrl.dispose();
    _hScrollCtrlBottom.dispose();
    _vScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tableWidth = widget.tableWidth;
    final zoomLevel = widget.zoomLevel;

    return Stack(
      children: [
        Positioned.fill(
          bottom: 14,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent &&
                  HardwareKeyboard.instance.isControlPressed) {
                final delta = event.scrollDelta.dy > 0 ? -0.1 : 0.1;
                widget.onZoomChanged((zoomLevel + delta).clamp(1.0, 2.0));
              }
            },
            child: GestureDetector(
              onScaleUpdate: (details) {
                if (details.pointerCount > 1) {
                  widget.onZoomChanged(
                    (zoomLevel * details.scale).clamp(1.0, 2.0),
                  );
                }
              },
              child: RawScrollbar(
                controller: _vScrollCtrl,
                thumbVisibility: true,
                thumbColor: Colors.blue,
                trackColor: Colors.blue.withOpacity(0.12),
                trackBorderColor: Colors.blue.withOpacity(0.3),
                radius: const Radius.circular(6),
                thickness: 10,
                child: SingleChildScrollView(
                  controller: _vScrollCtrl,
                  scrollDirection: Axis.vertical,
                  child: SizedBox(
                    height: _unscaledContentHeight > 0
                        ? (_unscaledContentHeight + 20) * zoomLevel
                        : null,
                    child: SingleChildScrollView(
                      controller: _hScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20, right: 20),
                        child: SizedBox(
                          width: (tableWidth + 20) * zoomLevel,
                          child: Transform.scale(
                            scale: zoomLevel,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              key: _contentKey,
                              width: tableWidth,
                              child: widget.content,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 14,
          child: Container(
            color: AppColors.cardBackground,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewportWidth = constraints.maxWidth;
                final contentWidth = (tableWidth + 20) * zoomLevel + 20;
                final minWidth = contentWidth > viewportWidth
                    ? contentWidth
                    : viewportWidth + 1;
                return RawScrollbar(
                  controller: _hScrollCtrlBottom,
                  thumbVisibility: true,
                  trackVisibility: true,
                  thumbColor: Colors.blue,
                  trackColor: Colors.blue.withOpacity(0.12),
                  trackBorderColor: Colors.blue.withOpacity(0.3),
                  radius: const Radius.circular(6),
                  thickness: 10,
                  child: SingleChildScrollView(
                    controller: _hScrollCtrlBottom,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: minWidth, height: 1),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Report Viewer Modal ──────────────────────────────────────────────────────

class ReportViewerModal extends StatefulWidget {
  const ReportViewerModal({
    super.key,
    required this.batch,
  });

  final ReportBatch batch;

  @override
  State<ReportViewerModal> createState() => _ReportViewerModalState();
}

class _ReportViewerModalState extends State<ReportViewerModal> {
  bool _loading = true;
  String? _error;
  Uint8List? _pdfBytes;

  ReportViewResponse? _viewData;
  TabController? _tabController;
  double _zoomLevel = 1.0;

  final _reportService = ReportService();

  static final Map<String, Uint8List> _pdfCache = {};

  String get _cacheKey =>
      '${widget.batch.reportType}_${widget.batch.reportVariant}_'
      '${widget.batch.periodYear}_${widget.batch.periodMonths}';

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    final cached = _pdfCache[_cacheKey];
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _pdfBytes = cached;
        _loading = false;
      });
      return;
    }

    try {
      final bytes = await _reportService.downloadReport(
        DownloadReportParams(
          reportType: widget.batch.reportType,
          reportVariant: widget.batch.reportVariant,
          periodYear: widget.batch.periodYear,
          periodMonths: widget.batch.periodMonths,
          format: 'pdf',
        ),
        timeout: const Duration(seconds: 120),
      );
      if (!mounted) return;

      _pdfCache[_cacheKey] = bytes;

      setState(() {
        _pdfBytes = bytes;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Report view error: $e');
      if (!mounted) return;
      final code = await classifyError(e);
      setState(() {
        if (code == 503) {
          _error =
              'No internet connection. Please check your network and try again.';
        } else if (code == 408) {
          _error = 'Request timed out. Please try again.';
        } else {
          _error = 'Something went wrong. Please try again.';
        }
        _loading = false;
      });
    }
  }

  Future<void> _handlePrint() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final isMobile = size.width < 900;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: isMobile
          ? EdgeInsets.only(top: topPadding)
          : const EdgeInsets.all(20),
      child: Container(
        width: isMobile ? size.width : size.width * 0.95,
        height: isMobile ? size.height - topPadding : size.height * 0.92,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(isMobile ? 0 : 16),
          border: isMobile ? null : Border.all(color: AppColors.cardBorder),
          boxShadow: isMobile
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
        ),
        child: Column(
          children: [
            _ModalHeader(
              batch: widget.batch,
              onClose: () => Navigator.pop(context),
              onPrint: _pdfBytes == null ? null : _handlePrint,
            ),
            const Divider(color: AppColors.cardBorder, height: 1),
            Expanded(
              child: _loading
                  ? const _LoadingView()
                  : _error != null
                  ? _ErrorView(
                      error: _error!,
                      onRetry: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                        });
                        _loadReport();
                      },
                    )
                  : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final bytes = _pdfBytes;
    if (bytes == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No data available for this report period.',
            style: TextStyle(color: AppColors.textGray, fontSize: 13),
          ),
        ),
      );
    }

    return PdfPreview(
      allowPrinting: false,
      allowSharing: false,
      useActions: false,
      canDebug: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      dpi: 200,
      loadingWidget: const _LoadingView(),
      build: (_) async => bytes,
    );
  }

  // ── Establishment header block ───────────────────────────────────────────
  // Mirrors the top of the DAE-1B sheet: report title, period, then the
  // establishment identity + room count.

  Widget _buildFormHeader(EstablishmentReport est) {
    final bizLines = est.businessLine ?? [];
    final accomTypes = [
      ('Hotel', 'hotel'),
      ('Resort', 'resort'),
      ('Pension Inn/ Lodge', 'pension_inn'),
      ('Youth Hostel/ Dormitory', 'youth_hostel'),
      ('Apartel/ Rented Homes/ Apartment', 'apartment'),
      ('Others, please specify: _________________________', 'others'),
    ];

    final ts = const TextStyle(
      fontFamily: _Dae.font,
      fontSize: _Dae.headerSize,
      color: _Dae.ink,
    );

    return Container(
      color: _Dae.paper,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: DAE-1B (Manual) — LEFT
          Text('DAE-1B (Manual)', style: ts),
          const SizedBox(height: 10),
          // Rows 3, 4, 5, 7 — CENTER
          Center(
            child: Column(
              children: [
                Text(
                  'Region: _4-A',
                  textAlign: TextAlign.center,
                  style: ts.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 50,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: _Var.ink, width: 1),
                    ),
                  ),
                  child: Text(
                    widget.batch.displayPeriod,
                    textAlign: TextAlign.center,
                    style: ts.copyWith(
                      fontStyle: FontStyle.italic,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '(Month, Year)',
                  textAlign: TextAlign.center,
                  style: ts.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                Text(
                  'REPORT ON THE REGIONAL DISTRIBUTION OF TRAVELERS',
                  textAlign: TextAlign.center,
                  style: ts.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: _Dae.titleSize,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Type of Accommodation — LEFT
          Text(
            'Type of Accommodation',
            style: ts.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          for (final entry in accomTypes)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: SizedBox(
                width: 360,
                child: Row(
                  children: [
                    Text(entry.$1, style: ts),
                    const Spacer(),
                    Container(
                      width: 25,
                      height: 14,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black, width: 0.8),
                      ),
                      child: bizLines.contains(entry.$2)
                          ? const Icon(Icons.check, size: 12, color: _Dae.ink)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          // DOT Accreditation Classification — LEFT
          Text(
            'DOT Accreditation Classification: _____________________________',
            style: ts.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          // AE ID Code (first) — LEFT
          Text(
            'AE ID Code (LGU Assigned): ${est.aeId ?? '_______________________________________'}',
            style: ts.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          // AE ID Code (second) — LEFT
          Text(
            'AE ID Code (LGU Assigned): ${est.aeId ?? '__________________________________________'}',
            style: ts.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          // City/Municipality — LEFT
          Text(
            'City/Municipality: ${est.cityMunicipality ?? '_________________'}',
            style: ts.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          // Province — LEFT
          Text(
            'Province: ${est.province ?? '___________________'}',
            style: ts.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildEstablishmentView(EstablishmentReport est) {
    final tableWidth = _computeTableWidth(est);

    return _EstablishmentView(
      tableWidth: tableWidth,
      zoomLevel: _zoomLevel,
      onZoomChanged: (z) => setState(() => _zoomLevel = z),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: tableWidth, child: _buildFormHeader(est)),
          _buildReportTable(est),
          SizedBox(width: tableWidth, child: _buildFooter()),
        ],
      ),
    );
  }

  // ── VAR Report Content ─────────────────────────────────────────────────────

  Widget _buildVarContent() {
    final data = _viewData!;
    final tableWidth = _varTableWidth();

    return _EstablishmentView(
      tableWidth: tableWidth,
      zoomLevel: _zoomLevel,
      onZoomChanged: (z) => setState(() => _zoomLevel = z),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVarFormHeader(),
          _VarReportTable(
            establishments: data.establishments,
            totals: data.totals.varData ?? const VarData(),
          ),
          _buildVarFooter(),
        ],
      ),
    );
  }

  double _varTableWidth() {
    return _Var.nameColWidth + _Var.attrCodeWidth + 15 * _Var.dataColWidth;
  }

  // ── VAR 1 (Tourist Attraction) Report Content ──────────────────────────────

  Widget _buildVar1View(EstablishmentReport est) {
    final tableWidth = _var1TableWidth();

    return _EstablishmentView(
      tableWidth: tableWidth,
      zoomLevel: _zoomLevel,
      onZoomChanged: (z) => setState(() => _zoomLevel = z),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVar1FormHeader(est),
          _Var1ReportTable(
            establishment: est,
            month: widget.batch.periodMonths.isNotEmpty
                ? widget.batch.periodMonths.first
                : 1,
            year: widget.batch.periodYear,
          ),
          _buildVar1Footer(),
        ],
      ),
    );
  }

  Widget _buildVar1Tabs(List<EstablishmentReport> establishments) {
    return Column(
      children: [
        SizedBox(
          height: 34,
          child: Material(
            color: AppColors.backgroundDark,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.primaryCyan,
              unselectedLabelColor: AppColors.textGray,
              indicatorColor: AppColors.primaryCyan,
              indicatorSize: TabBarIndicatorSize.label,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              labelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              tabAlignment: TabAlignment.start,
              tabs: establishments
                  .map((e) => Tab(text: e.businessName))
                  .toList(),
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: establishments
                .map((e) => _buildVar1View(e))
                .toList(),
          ),
        ),
      ],
    );
  }

  double _var1TableWidth() {
    return _Var1.tableWidth;
  }

  // ── VAR 1 Form Header (rows 1-14 of VAR-REPORT-ATTRACTION_DAILY.xlsx) ─────

  Widget _buildVar1FormHeader(EstablishmentReport est) {
    final ts = const TextStyle(
      fontFamily: _Var1.font,
      fontSize: 12,
      color: _Var1.ink,
    );
    final tsNarrow = const TextStyle(
      fontFamily: _Var1.narrow,
      fontSize: 11,
      color: _Var1.ink,
    );

    final month = widget.batch.periodMonths.isNotEmpty
        ? widget.batch.periodMonths.first
        : 1;
    const monthNames = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final period = '${monthNames[month]}, ${widget.batch.periodYear}';
    final types = (est.attractionType ?? [])
        .map(_attractionTypeLabel)
        .where((t) => t.isNotEmpty)
        .join(', ');

    return Container(
      color: _Var1.paper,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      width: _var1TableWidth(),
      child: Stack(
        children: [
          // Logo at top-LEFT, per same day blank.xlsx anchor (col C..E / rows 3-7).
          Positioned(
            top: 14,
            left: 93,
            child: Image.asset(
              'assets/images/tourism_office_logo.jpg',
              width: 143,
              height: 86,
              fit: BoxFit.contain,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Republic of the Philippines',
                  style: ts.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Center(
                child: Text(
                  'City Government of San Pablo',
                  style: ts.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              ...[
                'Tourism Information Center, Doña Leonila Park',
                'City Hall Compound, San Pablo City',
              ].map(
                (line) => Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      line,
                      style: ts,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ).toList(),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'OFFICE OF CITY TOURISM',
                  style: ts.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              // Title + (VAR 1) at far right (matches VAR 2's spaceBetween row)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tourism Attraction Visitor Record',
                    style: ts.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text('(VAR 1)', style: ts),
                ],
              ),
              const SizedBox(height: 4),
              // Subtitle (matches VAR 2's left-aligned note)
              Text(
                '( This recording form can be used instead of just counting the visitors )',
                style: tsNarrow,
              ),
              const SizedBox(height: 12),
              _var1Field('Month/Year:', period, underline: true),
              const SizedBox(height: 3),
              _var1Field('Name of City/Municipality:', 'SAN PABLO CITY', boxed: true),
              const SizedBox(height: 3),
              _var1Field('Name of attraction/ Spot:', est.businessName, underline: true),
              const SizedBox(height: 6),
              _var1Field(
                'Type of Tourism Attraction:',
                types.isEmpty ? '—' : types,
                boxed: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _var1Field(
    String label,
    String value, {
    bool underline = false,
    bool boxed = false,
  }) {
    final tsNarrow = const TextStyle(
      fontFamily: _Var1.narrow,
      fontSize: 11,
      color: _Var1.ink,
    );
    Widget valueWidget = Text(value, style: tsNarrow);
    if (underline) {
      valueWidget = Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.black, width: 1.2),
          ),
        ),
        child: valueWidget,
      );
    } else if (boxed) {
      valueWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.black, width: 1.2),
            bottom: BorderSide(color: Colors.black, width: 1.2),
          ),
        ),
        child: valueWidget,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: tsNarrow),
        const SizedBox(width: 20),
        SizedBox(
          width: 650,
          child: valueWidget,
        ),
      ],
    );
  }

  // ── VAR 1 Report Footer (rows 51-58) ───────────────────────────────────────

  Widget _buildVar1Footer() {
    final ts = const TextStyle(
      fontFamily: _Var1.font,
      fontSize: 12,
      color: _Var1.ink,
    );
    final tsNarrow = const TextStyle(
      fontFamily: _Var1.narrow,
      fontSize: 9,
      color: _Var1.ink,
    );

    return Container(
      color: _Var1.paper,
      width: _var1TableWidth(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Note: *Total number must be recorded,  ** Sex & ***Residence entries are optional.   Total number of this month must be reported.',
            style: tsNarrow,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text('Prepared by:', style: ts),
                    const SizedBox(height: 30),
                    Text('________________________', style: ts),
                    const SizedBox(height: 2),
                    Text(
                      'ROMINA I. ALIDIO',
                      style: ts.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Admin Aide I',
                      style: ts.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text('Received and checked by:', style: ts),
                    const SizedBox(height: 30),
                    Text('________________________', style: ts),
                    const SizedBox(height: 2),
                    Text(
                      'REINA KRISTINE S. OLIVA',
                      style: ts.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Admin Aide VI',
                      style: ts.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // QR code below signatures (same day blank.xlsx rows 62-64, col B..F).
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 43),
            child: Image.asset(
              'assets/images/qr-pic.png',
              width: 210,
              height: 58,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'QFM-OCT-002 Rev 0 2022.02.16',
            style: ts.copyWith(fontSize: 8),
          ),
        ],
      ),
    );
  }

  // ── VAR Form Header (rows 1-11 of VAR-REPORT.xlsx) ────────────────────────

  Widget _buildVarFormHeader() {
    final ts = const TextStyle(
      fontFamily: _Var.font,
      fontSize: 12,
      color: _Var.ink,
    );

    final month = widget.batch.periodMonths.isNotEmpty
        ? widget.batch.periodMonths.first
        : 1;
    const monthNames = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const monthAbbr = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final year = widget.batch.periodYear;
    final monthLabel = widget.batch.periodMonths.length == 1
        ? '${monthNames[month]}, $year'
        : '${monthAbbr[widget.batch.periodMonths.first]}-${monthAbbr[widget.batch.periodMonths.last]}, $year';

    return Container(
      color: _Var.paper,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      width: _varTableWidth(),
      child: Stack(
        children: [
          Positioned(
            top: 5,
            left: 70,
            child: Image.asset(
              'assets/images/tourism_office_logo.jpg',
              width: 50,
              height: 50,
              fit: BoxFit.contain,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Republic of the Philippines
              Center(
                child: Text(
                  'Republic of the Philippines',
                  style: ts.copyWith(fontSize: 12),
                ),
              ),
              const SizedBox(height: 2),
              // Row 2: City Government
              Center(
                child: Text(
                  'City Government of San Pablo',
                  style: ts.copyWith(fontSize: 12),
                ),
              ),
              const SizedBox(height: 2),
              // Row 3: Address
              Center(
                child: Text(
                  'Information Center, Do\u00f1a Leonila Park, City Hall Compound, San Pablo City ',
                  style: ts.copyWith(fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 2),
              // Row 4: Email/contact
              Center(
                child: Text(
                  'e-mail: tourism.sanpablo@yahoo.com Tel./Fax No.: (049)562-1429',
                  style: ts.copyWith(
                    fontSize: 10,
                    decoration: TextDecoration.underline,
                    color: _Var.emailBlue,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              // Row 6: Tourism Attraction Visitor Record
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tourism Attraction Visitor Record',
                    style: ts.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text('VAR 2', style: ts),
                ],
              ),
              const SizedBox(height: 4),
              // Row 7: Note
              Text(
                '( This recording form can be used instead of just counting the visitors )',
                style: ts.copyWith(fontSize: _Var.smallSize),
              ),
              const SizedBox(height: 12),
              // Row 9: Month/Year
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Month/Year:', style: ts),
                  const SizedBox(width: 20),
                  Container(
                    width: 650,
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _Var.ink, width: 1),
                      ),
                    ),
                    child: Text(
                      monthLabel,
                      style: ts.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.start,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Row 10: Name of Municipality
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Name of Municipality:', style: ts),
                  const SizedBox(width: 20),
                  Container(
                    width: 650,
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _Var.ink, width: 1),
                      ),
                    ),
                    child: Text(
                      'SAN PABLO CITY',
                      style: ts.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ],
      ),
    );
  }

  // ── VAR Footer (rows 58-65 of VAR-REPORT.xlsx) ───────────────────────────

  Widget _buildVarFooter() {
    final ts = const TextStyle(
      fontFamily: _Var.font,
      fontSize: 10,
      color: _Var.ink,
    );

    return Container(
      color: _Var.paper,
      width: _varTableWidth(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Note: *Total number must be recorded, ** Sex & ***Residence entries are optional. ****Total number of this month must be reported.',
            style: ts.copyWith(fontSize: _Var.smallSize),
          ),
          const SizedBox(height: 16),
          // Signature lines
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text('Prepared by:', style: ts),
                    const SizedBox(height: 30),
                    Text('________________________', style: ts),

                    Text(
                      'ADMINISTRATIVE AIDE 1',
                      style: ts.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text('Check and Submitted by:', style: ts),
                    const SizedBox(height: 30),
                    Text('________________________', style: ts),

                    Text(
                      'LOCAL REGISTRY COLLECTION OFFICER I',
                      style: ts.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text('Noted by:', style: ts),
                    const SizedBox(height: 30),
                    Text('________________________', style: ts),

                    Text(
                      'City Tourism Officer CGDH-1',
                      style: ts.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('QFM-OCT-006 Rev 0 2022.02.16', style: ts.copyWith(fontSize: 8)),
        ],
      ),
    );
  }

  double _computeTableWidth(EstablishmentReport est) {
    int dayColCount;
    bool showTotal;
    switch (widget.batch.reportVariant) {
      case 'daily':
        final year = widget.batch.periodYear;
        final month = widget.batch.periodMonths.first;
        dayColCount = DateTime(year, month + 1, 0).day;
        showTotal = true;
      case 'summary':
        return 414.0 + 131.0;
      case 'series':
        dayColCount = est.seriesData?.length ?? 0;
        showTotal = true;
        final seriesMonthWidth = _dayColWidth * 1.5;
        final seriesTotalWidth = seriesMonthWidth * 0.9;
        return _labelColWidth +
            dayColCount * seriesMonthWidth +
            seriesTotalWidth;
      default:
        dayColCount = 0;
        showTotal = false;
    }
    return _labelColWidth +
        dayColCount * _dayColWidth +
        (showTotal ? _totalColWidth : 0);
  }

  Widget _buildFooter() {
    final isDaily = widget.batch.reportVariant == 'daily';
    final ts = const TextStyle(
      fontFamily: _Dae.font,
      fontSize: 10,
      color: _Dae.ink,
    );

    if (isDaily) {
      return Container(
        color: _Dae.paper,
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prepared by:            ____________________________________                         ________________________________________                         ____________________________________',
              style: ts,
            ),
            const SizedBox(height: 4),
            const Text(
              '                                                      Signature over Printed Name                                                     Position/Designation',
              style: TextStyle(
                fontFamily: _Dae.font,
                fontSize: 10,
                color: _Dae.ink,
              ),
            ),
          ],
        ),
      );
    }

    // Summary / Monthly footer (matches rows 176-181 of the template)
    return Container(
      color: _Dae.paper,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text('Date Submitted:     ____________________', style: ts),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Prepared by:        ____________________________________',
                style: ts,
              ),
              const SizedBox(width: 24),
              Text('________________', style: ts),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.center,
            child: Text('Signature over Printed Name', style: ts),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.center,
            child: Text('___________________________________', style: ts),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.center,
            child: Text('Position/Designation', style: ts),
          ),
        ],
      ),
    );
  }

  // ── Variant → sheet mapping ────────────────────────────────────────────
  // daily   -> "Name of Establishment" sheet  (day columns 1-31 + TOTAL)
  // summary -> "AE DAE-1B by Country (Sum)"   (single TOTAL column)
  // series  -> "AE DAE-1B (Monthly)"          (Jan-Dec columns + TOTAL)

  Widget _buildReportTable(EstablishmentReport est) {
    final md = est.monthData;
    if (md == null && widget.batch.reportVariant != 'series') {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No data available for this report period.',
            style: TextStyle(
              fontFamily: _Dae.font,
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    switch (widget.batch.reportVariant) {
      case 'daily':
        final year = widget.batch.periodYear;
        final month = widget.batch.periodMonths.first;
        final daysInMonth = DateTime(year, month + 1, 0).day;
        final cols = [
          for (int d = 1; d <= daysInMonth; d++) _ColumnSpec('$d', md!, '$d'),
        ];
        return _ReportTable(est: est, columns: cols, showTotalColumn: true);

      case 'summary':
        final cols = [_ColumnSpec('TOTAL', md!, '0')];
        return _ReportTable(
          est: est,
          columns: cols,
          showTotalColumn: false,
          labelColWidth: 414,
          dataColWidth: 131,
        );

      case 'series':
        const monthNames = [
          '',
          'JANUARY',
          'FEBRUARY',
          'MARCH',
          'APRIL',
          'MAY',
          'JUNE',
          'JULY',
          'AUGUST',
          'SEPTEMBER',
          'OCTOBER',
          'NOVEMBER',
          'DECEMBER',
        ];
        final series = est.seriesData ?? const <MonthSeriesEntry>[];
        final cols = [
          for (final s in series) _ColumnSpec(monthNames[s.month], s.data, '0'),
        ];
        final seriesMonthWidth = _dayColWidth * 1.5;
        final seriesTotalWidth = seriesMonthWidth * 0.9;
        return _ReportTable(
          est: est,
          columns: cols,
          showTotalColumn: true,
          dataColWidth: seriesMonthWidth,
          totalColWidth: seriesTotalWidth,
        );

      default:
        return const Center(
          child: Text(
            'Unknown variant',
            style: TextStyle(fontFamily: _Dae.font),
          ),
        );
    }
  }
}

// ── Modal Header ──────────────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({
    required this.batch,
    required this.onClose,
    required this.onPrint,
  });

  final ReportBatch batch;
  final VoidCallback onClose;
  final VoidCallback? onPrint;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    final iconSize = isMobile ? 28.0 : 36.0;
    final iconInnerSize = isMobile ? 14.0 : 18.0;
    final titleFontSize = isMobile ? 13.0 : 15.0;
    final badgeFontSize = isMobile ? 10.0 : 11.0;
    final subtitleFontSize = isMobile ? 10.0 : 11.5;
    final btnSize = isMobile ? 28.0 : 32.0;
    final btnIconSize = isMobile ? 14.0 : 16.0;
    final horizontalPad = isMobile ? 10.0 : 20.0;
    final verticalPad = isMobile ? 8.0 : 16.0;

    final titleSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: isMobile ? 6 : 8,
          runSpacing: 4,
          children: [
            Text(
              '${batch.reportType == "var1" ? "VAR 1" : batch.reportType == "var2" ? "VAR 2" : "DAE"} \u2014 ${batch.variantLabel}',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 5 : 7,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryCyan.withOpacity(0.10),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: AppColors.primaryCyan.withOpacity(0.25),
                ),
              ),
              child: Text(
                batch.displayPeriod,
                style: TextStyle(
                  color: AppColors.primaryCyan,
                  fontSize: badgeFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: isMobile ? 1 : 2),
        Text(
          'Live data \u2014 Batch: ${batch.shortId}',
          style: TextStyle(
            color: AppColors.textGray,
            fontSize: subtitleFontSize,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );

    final printButton = GestureDetector(
      onTap: onPrint,
      child: AnimatedOpacity(
        opacity: onPrint != null ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: btnSize,
          height: btnSize,
          decoration: BoxDecoration(
            color: AppColors.backgroundDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Icon(
            Icons.print_rounded,
            color: AppColors.textGray,
            size: btnIconSize,
          ),
        ),
      ),
    );

    final closeButton = GestureDetector(
      onTap: onClose,
      child: Container(
        width: btnSize,
        height: btnSize,
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Icon(
          Icons.close_rounded,
          color: AppColors.textGray,
          size: btnIconSize,
        ),
      ),
    );

    if (isMobile) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPad,
          verticalPad,
          horizontalPad,
          verticalPad,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: AppColors.primaryCyan.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.table_chart_rounded,
                    color: AppColors.primaryCyan,
                    size: iconInnerSize,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: titleSection),
                const SizedBox(width: 8),
                printButton,
                const SizedBox(width: 6),
                closeButton,
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPad,
        verticalPad,
        horizontalPad,
        verticalPad,
      ),
      child: Row(
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: AppColors.primaryCyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.table_chart_rounded,
              color: AppColors.primaryCyan,
              size: iconInnerSize,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: titleSection),
          const SizedBox(width: 12),
          printButton,
          const SizedBox(width: 8),
          closeButton,
        ],
      ),
    );
  }
}
// ── Loading & Error Views ─────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: AppColors.primaryCyan,
            strokeWidth: 2,
          ),
          SizedBox(height: 14),
          Text(
            'Loading report data\u2026',
            style: TextStyle(color: AppColors.textGray, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, this.onRetry});
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFF4D6A),
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load the report.',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryCyan,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
