import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/core/services/connectivity_service.dart';
import 'package:app/api/admin_report_api.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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
// Lifted from VAR-REPORT-ATTRACTION_DAILY.xlsx: yellow header (#FFFF00),
// green total (#92D050), Arial throughout.  Day column = B (narrow), a
// "Week Day" column = C, then 15 data columns (D..R).
// ─────────────────────────────────────────────────────────────────────────
class _Var1 {
  static const String font = 'Arial';
  static const Color paper = Colors.white;
  static const Color ink = Colors.black;
  static const Color gridLine = Colors.black;
  static const Color headerYellow = Color(0xFFFFFF00);
  static const Color totalGreen = Color(0xFF92D050);
  static const double dataSize = 8.5;
  static const double daySize = 10.0;
  static const double headerSize = 8.5;
  static const double smallSize = 9.0;

  static const double dayColWidth = 32;
  static const double weekdayColWidth = 78;
  static const double dataColWidth = 55;
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
  bool bold = false,
  double height = 17,
  bool isTotal = false,
  bool day = false,
}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: isTotal ? _Var1.totalGreen : _Var1.paper,
      border: Border.all(color: _Var1.gridLine, width: 0.5),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: _Var1.font,
        fontSize: day ? _Var1.daySize : _Var1.dataSize,
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
  double height = 20,
}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _Var1.headerYellow,
      border: Border.all(color: _Var1.gridLine, width: 0.5),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
    child: Text(
      text,
      textAlign: TextAlign.center,
      softWrap: wrap,
      overflow: TextOverflow.clip,
      style: TextStyle(
        fontFamily: _Var1.font,
        fontSize: _Var1.headerSize,
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

  static const double _dayW = _Var1.dayColWidth;
  static const double _wdW = _Var1.weekdayColWidth;
  static const double _dataW = _Var1.dataColWidth;

  static const double _h1 = 20.0;
  static const double _h2 = 18.0;
  static const double _h3 = 30.0;
  static const double _h4 = 20.0;
  static const double _headerH = _h1 + _h2 + _h3 + _h4;

  static const double _tableW = _dayW + _wdW + 15 * _dataW;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_buildHeader(), _buildDataSection()],
    );
  }

  Widget _buildHeader() {
    const double xDay = 0;
    const double xWd = _dayW;
    const double xData = _dayW + _wdW;
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
    }) {
      return Positioned(
        left: x,
        top: y,
        width: w,
        height: h,
        child: _var1HeaderCell(text, width: w, height: h, wrap: wrap),
      );
    }

    return SizedBox(
      width: _tableW,
      height: _headerH,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // ── Row 1 (y=0): "Date" spans B16:C16 ────────────────────────
          cell('Date', x: xDay, y: y0, w: _dayW + _wdW, h: _h1),
          // D16:O16 = "*** Place of Residence"
          cell('*** Place of Residence', x: xData, y: y0, w: _dataW * 12, h: _h1),
          // P16:R18 = "* Grand Total Number of Visitors" (3 rows)
          cell(
            '* Grand Total Number of Visitors',
            x: xData + _dataW * 12,
            y: y0,
            w: _dataW * 3,
            h: _h1 + _h2 + _h3,
            wrap: true,
          ),

          // ── Row 2 (y=20) ─────────────────────────────────────────────
          // B17:B19 = "Day" (3 rows)
          cell('Day', x: xDay, y: y1, w: _dayW, h: _h2 + _h3 + _h4, wrap: true),
          // C17:C19 = "Week Day (Mon-Sun)" (3 rows)
          cell(
            'Week Day (Mon-Sun)',
            x: xWd,
            y: y1,
            w: _wdW,
            h: _h2 + _h3 + _h4,
            wrap: true,
          ),
          // D17:L17 = "Philippines"
          cell('Philippines', x: xData, y: y1, w: _dataW * 9, h: _h2),
          // M17:O18 = "Foreign Country Residence" (2 rows)
          cell(
            'Foreign Country Residence',
            x: xData + _dataW * 9,
            y: y1,
            w: _dataW * 3,
            h: _h2 + _h3,
            wrap: true,
          ),

          // ── Row 3 (y=38) ─────────────────────────────────────────────
          cell(
            'This City/Municipality',
            x: xData,
            y: y2,
            w: _dataW * 3,
            h: _h3,
            wrap: true,
          ),
          cell(
            'Other City/Municipality',
            x: xData + _dataW * 3,
            y: y2,
            w: _dataW * 3,
            h: _h3,
            wrap: true,
          ),
          cell('Other Province', x: xData + _dataW * 6, y: y2, w: _dataW * 3, h: _h3),

          // ── Row 4 (y=68): M / F / T for each of the 5 groups ────────
          for (int g = 0; g < 5; g++) ...[
            cell('Male', x: xData + _dataW * (g * 3), y: y3, w: _dataW, h: _h4),
            cell('Female', x: xData + _dataW * (g * 3 + 1), y: y3, w: _dataW, h: _h4),
            cell('Total', x: xData + _dataW * (g * 3 + 2), y: y3, w: _dataW, h: _h4),
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

    String v(int val) => val == 0 ? '' : '$val';

    return Row(
      children: [
        _var1DataCell(isInMonth ? '$day' : '', width: _dayW, day: true),
        _var1DataCell(
          isInMonth ? _weekdayLabel(year, month, day) : '',
          width: _wdW,
          day: true,
        ),
        _var1DataCell(v(m.maleThisCity), width: _dataW),
        _var1DataCell(v(m.femaleThisCity), width: _dataW),
        _var1DataCell(m.totalThisCity == 0 ? '' : '${m.totalThisCity}', width: _dataW),
        _var1DataCell(v(m.maleOtherCity), width: _dataW),
        _var1DataCell(v(m.femaleOtherCity), width: _dataW),
        _var1DataCell(m.totalOtherCity == 0 ? '' : '${m.totalOtherCity}', width: _dataW),
        _var1DataCell(v(m.maleOtherProvince), width: _dataW),
        _var1DataCell(v(m.femaleOtherProvince), width: _dataW),
        _var1DataCell(m.totalOtherProvince == 0 ? '' : '${m.totalOtherProvince}', width: _dataW),
        _var1DataCell(v(m.maleForeign), width: _dataW),
        _var1DataCell(v(m.femaleForeign), width: _dataW),
        _var1DataCell(m.totalForeign == 0 ? '' : '${m.totalForeign}', width: _dataW),
        _var1DataCell(v(m.grandMale), width: _dataW),
        _var1DataCell(v(m.grandFemale), width: _dataW),
        _var1DataCell(m.grandTotal == 0 ? '' : '${m.grandTotal}', width: _dataW),
      ],
    );
  }

  Row _buildTotalRow() {
    final t = establishment.attractionTotals ?? const VarData();
    String v(int x) => '$x';
    return Row(
      children: [
        _var1DataCell(
          'Total of this Month ****',
          width: _dayW + _wdW,
          bold: true,
          isTotal: true,
        ),
        _var1DataCell(v(t.maleThisCity), width: _dataW, isTotal: true),
        _var1DataCell(v(t.femaleThisCity), width: _dataW, isTotal: true),
        _var1DataCell(v(t.totalThisCity), width: _dataW, isTotal: true),
        _var1DataCell(v(t.maleOtherCity), width: _dataW, isTotal: true),
        _var1DataCell(v(t.femaleOtherCity), width: _dataW, isTotal: true),
        _var1DataCell(v(t.totalOtherCity), width: _dataW, isTotal: true),
        _var1DataCell(v(t.maleOtherProvince), width: _dataW, isTotal: true),
        _var1DataCell(v(t.femaleOtherProvince), width: _dataW, isTotal: true),
        _var1DataCell(v(t.totalOtherProvince), width: _dataW, isTotal: true),
        _var1DataCell(v(t.maleForeign), width: _dataW, isTotal: true),
        _var1DataCell(v(t.femaleForeign), width: _dataW, isTotal: true),
        _var1DataCell(v(t.totalForeign), width: _dataW, isTotal: true),
        _var1DataCell(v(t.grandMale), width: _dataW, isTotal: true),
        _var1DataCell(v(t.grandFemale), width: _dataW, isTotal: true),
        _var1DataCell(v(t.grandTotal), width: _dataW, isTotal: true),
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
    required this.onDownload,
  });

  final ReportBatch batch;
  final void Function(String format) onDownload;

  @override
  State<ReportViewerModal> createState() => _ReportViewerModalState();
}

class _ReportViewerModalState extends State<ReportViewerModal>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  ReportViewResponse? _viewData;

  bool _downloading = false;
  bool _printing = false;
  TabController? _tabController;

  double _zoomLevel = 1.0;
  static const double _zoomStep = 0.1;
  static const double _zoomMin = 1.0;
  static const double _zoomMax = 2.0;

  void _zoomIn() => setState(
    () => _zoomLevel = (_zoomLevel + _zoomStep).clamp(_zoomMin, _zoomMax),
  );
  void _zoomOut() => setState(
    () => _zoomLevel = (_zoomLevel - _zoomStep).clamp(_zoomMin, _zoomMax),
  );
  void _resetZoom() => setState(() => _zoomLevel = 1.0);

  final _reportService = ReportService();

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    try {
      final params = ViewReportParams(
        reportType: widget.batch.reportType,
        reportVariant: widget.batch.reportVariant,
        periodYear: widget.batch.periodYear,
        periodMonths: widget.batch.periodMonths,
      );
      final data = await _reportService.viewReport(params);
      if (!mounted) return;

      setState(() {
        _viewData = data;
        _loading = false;
      });

      if (data.establishments.length > 1) {
        _tabController = TabController(
          length: data.establishments.length,
          vsync: this,
        );
      }
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

  Future<void> _handleDownload(String format) async {
    setState(() => _downloading = true);
    try {
      widget.onDownload(format);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _handlePrint() async {
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        name: '${widget.batch.reportType == "var2"
            ? "VAR2"
            : widget.batch.reportType == "var1" ? "VAR1" : "DAE"}_Report',
        onLayout: (format) async {
          final pdfBytes = await _reportService.downloadReport(
            DownloadReportParams(
              reportType: widget.batch.reportType,
              reportVariant: widget.batch.reportVariant,
              periodYear: widget.batch.periodYear,
              periodMonths: widget.batch.periodMonths,
              format: 'pdf',
              pageWidth: format.width,
              pageHeight: format.height,
            ),
          );
          return pdfBytes;
        },
      );
    } catch (e) {
      debugPrint('Print error: $e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
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
              onDownloadExcel: _downloading
                  ? null
                  : () => _handleDownload('xlsx'),
              onDownloadPdf: _downloading ? null : () => _handleDownload('pdf'),
              onPrint: (_viewData == null || _printing) ? null : _handlePrint,
              downloading: _downloading,
              printing: _printing,
              zoomLevel: _zoomLevel,
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onZoomReset: _resetZoom,
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
    final data = _viewData!;
    final establishments = data.establishments;

    if (establishments.isEmpty) {
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

    // VAR 2: single table with all establishments + attractions
    if (widget.batch.reportType == 'var2') {
      return _buildVarContent();
    }

    // VAR 1 (tourist attraction): single grid or tab bar
    if (widget.batch.reportType == 'var1') {
      if (establishments.length == 1) {
        return _buildVar1View(establishments.first);
      }
      return _buildVar1Tabs(establishments);
    }

    // DAE: single establishment or tabs
    if (establishments.length == 1) {
      return _buildEstablishmentView(establishments.first);
    }

    // Multiple establishments: tab bar
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
                .map((e) => _buildEstablishmentView(e))
                .toList(),
          ),
        ),
      ],
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
    return _Var1.dayColWidth + _Var1.weekdayColWidth + 15 * _Var1.dataColWidth;
  }

  // ── VAR 1 Form Header (rows 1-14 of VAR-REPORT-ATTRACTION_DAILY.xlsx) ─────

  Widget _buildVar1FormHeader(EstablishmentReport est) {
    final ts = const TextStyle(
      fontFamily: _Var1.font,
      fontSize: 12,
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
          Positioned(
            top: 5,
            right: 70,
            child: Image.asset(
              'assets/images/tourism_office_logo.jpg',
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Republic of the Philippines',
                  style: ts.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Center(
                child: Text(
                  'City Government of San Pablo',
                  style: ts.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
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
                      style: ts.copyWith(fontSize: 10),
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
              // Row 7: title + (VAR 1) at far right
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Tourism Attraction Visitor Record',
                        style: ts.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Text(
                      '(VAR 1)',
                      style: ts.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Row 8: subtitle
              Center(
                child: Text(
                  '( This recording form can be used instead of just counting the visitors )',
                  style: ts.copyWith(fontSize: 9),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              // Rows 10-14: variable fields
              Text('Month/Year: $period', style: ts),
              const SizedBox(height: 3),
              Text('Name of City/Municipality:  SAN PABLO CITY', style: ts),
              const SizedBox(height: 3),
              Text('Name of attraction/ Spot:  ${est.businessName}', style: ts),
              const SizedBox(height: 6),
              Text(
                'Type of Tourism Attraction: ${types.isEmpty ? '—' : types}',
                style: ts.copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── VAR 1 Report Footer (rows 51-58) ───────────────────────────────────────

  Widget _buildVar1Footer() {
    final ts = const TextStyle(
      fontFamily: _Var1.font,
      fontSize: 10,
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
            '*Grand Total of this Month must be reported. **Sex & ***Residence entries are optional.',
            style: ts.copyWith(fontSize: _Var1.smallSize),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text('Submitted by:', style: ts),
                    const SizedBox(height: 30),
                    Text('________________________', style: ts),
                    Text(
                      'Tourism Staff',
                      style: ts.copyWith(fontWeight: FontWeight.bold, fontSize: 12),
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
                    Text(
                      'Administrative Aide VI',
                      style: ts.copyWith(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.center,
            child: Text(
              'QFM-OCT-006 Rev 0 2022.02.16',
              style: ts.copyWith(fontSize: 11),
            ),
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
    required this.onDownloadExcel,
    required this.onDownloadPdf,
    required this.onPrint,
    required this.downloading,
    required this.printing,
    required this.zoomLevel,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
  });

  final ReportBatch batch;
  final VoidCallback onClose;
  final VoidCallback? onDownloadExcel;
  final VoidCallback? onDownloadPdf;
  final VoidCallback? onPrint;
  final bool downloading;
  final bool printing;
  final double zoomLevel;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;

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
    final zoomTextSize = isMobile ? 10.0 : 11.0;
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

    final zoomControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onZoomOut,
          child: Container(
            width: btnSize,
            height: btnSize,
            decoration: BoxDecoration(
              color: AppColors.backgroundDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Icon(
              Icons.remove,
              color: AppColors.textGray,
              size: btnIconSize,
            ),
          ),
        ),
        SizedBox(width: isMobile ? 2 : 4),
        GestureDetector(
          onTap: onZoomReset,
          child: Container(
            height: btnSize,
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 6 : 8),
            decoration: BoxDecoration(
              color: AppColors.backgroundDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Center(
              child: Text(
                '${(zoomLevel * 100).round()}%',
                style: TextStyle(
                  color: AppColors.textGray,
                  fontSize: zoomTextSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: isMobile ? 2 : 4),
        GestureDetector(
          onTap: onZoomIn,
          child: Container(
            width: btnSize,
            height: btnSize,
            decoration: BoxDecoration(
              color: AppColors.backgroundDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Icon(
              Icons.add,
              color: AppColors.textGray,
              size: btnIconSize,
            ),
          ),
        ),
      ],
    );

    final downloadButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DownloadButton(
          icon: Icons.table_rows_rounded,
          label: 'Excel',
          color: const Color(0xFF1D6F42),
          isLoading: downloading,
          onTap: onDownloadExcel,
          compact: isMobile,
        ),
        SizedBox(width: isMobile ? 6 : 8),
        _DownloadButton(
          icon: Icons.picture_as_pdf_rounded,
          label: 'PDF',
          color: const Color(0xFFD32F2F),
          isLoading: downloading,
          onTap: onDownloadPdf,
          compact: isMobile,
        ),
        SizedBox(width: isMobile ? 6 : 8),
        _DownloadButton(
          icon: Icons.print_rounded,
          label: 'Print',
          color: const Color(0xFF1565C0),
          isLoading: printing,
          onTap: onPrint,
          compact: isMobile,
        ),
      ],
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
                closeButton,
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [downloadButtons, const Spacer(), zoomControls]),
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
          downloadButtons,
          const SizedBox(width: 12),
          zoomControls,
          const SizedBox(width: 12),
          closeButton,
        ],
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isLoading = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !isLoading;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 14,
            vertical: compact ? 5 : 8,
          ),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: compact ? 11 : 13,
                  height: compact ? 11 : 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, color: color, size: compact ? 12 : 14),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
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
