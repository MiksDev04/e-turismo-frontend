import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/core/services/connectivity_service.dart';
import 'package:app/api/admin_report_api.dart';

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

typedef _Getter = num Function(EstablishmentReport est, MonthData md, String day);

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
  'BRUNEI', 'CAMBODIA', 'INDONESIA', 'LAOS', 'MALAYSIA', 'MYANMAR',
  'SINGAPORE', 'THAILAND', 'VIETNAM',
];
const List<String> _kEastAsia = ['CHINA', 'HONGKONG', 'JAPAN', 'KOREA', 'TAIWAN'];
const List<String> _kSouthAsia = [
  'BANGLADESH', 'INDIA', 'IRAN', 'NEPAL', 'PAKISTAN', 'SRI LANKA',
];
const List<String> _kMiddleEast = [
  'BAHRAIN', 'EGYPT', 'ISRAEL', 'JORDAN', 'KUWAIT', 'SAUDI ARABIA',
  'UNITED ARAB EMIRATES',
];
const List<String> _kNorthAmerica = ['CANADA', 'MEXICO', 'USA'];
const List<String> _kSouthAmerica = ['ARGENTINA', 'BRAZIL', 'COLOMBIA', 'PERU', 'VENEZUELA'];
const List<String> _kWesternEurope = [
  'AUSTRIA', 'BELGIUM', 'FRANCE', 'GERMANY', 'LUXEMBOURG', 'NETHERLANDS', 'SWITZERLAND',
];
const List<String> _kNorthernEurope = [
  'DENMARK', 'FINLAND', 'IRELAND', 'NORWAY', 'SWEDEN', 'UNITED KINGDOM',
];
const List<String> _kSouthernEurope = [
  'GREECE', 'ITALY', 'PORTUGAL', 'SPAIN', 'UNION OF SERBIA AND MONTENEGRO',
];
const List<String> _kEasternEurope = [
  'COMMONWEALTH OF INDEPENDENT STATES', 'POLAND', 'RUSSIA',
];
const List<String> _kAustralasia = [
  'AUSTRALIA', 'GUAM', 'NAURU', 'NEW ZEALAND', 'PAPUA NEW GUINEA',
];
const List<String> _kAfrica = ['NIGERIA', 'SOUTH AFRICA'];

const List<String> _kAllCountries = [
  ..._kAsean, ..._kEastAsia, ..._kSouthAsia, ..._kMiddleEast,
  ..._kNorthAmerica, ..._kSouthAmerica,
  ..._kWesternEurope, ..._kNorthernEurope, ..._kSouthernEurope, ..._kEasternEurope,
  ..._kAustralasia, ..._kAfrica,
];

// ─────────────────────────────────────────────────────────────────────────
// VALUE HELPERS
// day == '0' is treated as "the aggregate for this snapshot" (matches the
// convention already used elsewhere in this app for residentsByDay/'0').
// ─────────────────────────────────────────────────────────────────────────
int _res(MonthData md, String day, String key) => md.residentsByDay?[day]?[key] ?? 0;

String _titleCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
    .join(' ');

int _country(MonthData md, String day, String name) {
  final byCountry = md.countryByDay;
  if (byCountry == null) return 0;
  final dayMap = byCountry[name] ?? byCountry[name.toUpperCase()] ?? byCountry[_titleCase(name)];
  return dayMap?[day] ?? 0;
}

int _sumCountries(MonthData md, String day, List<String> names) =>
    names.fold<int>(0, (sum, n) => sum + _country(md, day, n));

int _totalPh(EstablishmentReport est, MonthData md, String day) =>
    _res(md, day, 'philippine_resident_filipino') + _res(md, day, 'philippine_resident_foreign');

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
    _totalPh(est, md, day) + _totalNonPh(est, md, day) + _overseasFil(est, md, day) + _unspecifiedGuest(est, md, day);

int _roomsOccupied(EstablishmentReport est, MonthData md, String day) =>
    day == '0' ? md.totalRoomsOccupied : (md.roomsOccupied?[day] ?? 0);

// Matches this app's existing "rooms available" approximation (totalRooms *
// 30 for a full-period aggregate); a single day simply has totalRooms open.
int _roomsAvailable(EstablishmentReport est, MonthData md, String day) =>
    day == '0' ? est.totalRooms * 30 : est.totalRooms;

int _guestNights(EstablishmentReport est, MonthData md, String day) =>
    day == '0' ? (md.guestNights ?? 0) : (md.guestNightsByDay?[day] ?? 0);

double _occupancyRate(EstablishmentReport est, MonthData md, String day) {
  final avail = _roomsAvailable(est, md, day);
  if (avail == 0) return 0;
  return _roomsOccupied(est, md, day) / avail * 100;
}

double _avgLengthOfStay(EstablishmentReport est, MonthData md, String day) {
  final guests = _grandTotal(est, md, day);
  if (guests == 0) return 0;
  return _guestNights(est, md, day) / guests;
}

// NOTE: assumes md.sexByDay[day][sex] is keyed the same way as the
// residency categories above ('philippine_residents' / 'foreign_residents'
// / 'overseas_filipinos' / 'unspecified_guest'). Adjust these keys if the
// API uses different names for the per-sex breakdown.
int _sexCategory(MonthData md, String day, String sex, String category) =>
    md.sexByDay?[day]?[sex]?[category] ?? 0;

int _maleTotal(EstablishmentReport est, MonthData md, String day) =>
    _sexCategory(md, day, 'male', 'philippine_residents') +
    _sexCategory(md, day, 'male', 'foreign_residents') +
    _sexCategory(md, day, 'male', 'overseas_filipinos') +
    _sexCategory(md, day, 'male', 'unspecified_guest');

int _femaleTotal(EstablishmentReport est, MonthData md, String day) =>
    _sexCategory(md, day, 'female', 'philippine_residents') +
    _sexCategory(md, day, 'female', 'foreign_residents') +
    _sexCategory(md, day, 'female', 'overseas_filipinos') +
    _sexCategory(md, day, 'female', 'unspecified_guest');

// ─────────────────────────────────────────────────────────────────────────
// ROW LIST — mirrors "COUNTRY OF RESIDENCE" rows 25-149, then Part II
// rows 151-175 of the template, in exact order.
// ─────────────────────────────────────────────────────────────────────────
List<_RRow> _regionBlock(String name, List<String> countries, {bool asTopCategory = false}) {
  return [
    _RRow(name, asTopCategory ? _RKind.topCategory : _RKind.subCategory, indent: asTopCategory ? 0 : 1),
    ...countries.map(
      (c) => _RRow(c, _RKind.dataLeaf, indent: 2, value: (est, md, day) => _country(md, day, c)),
    ),
    _RRow('SUB-TOTAL', _RKind.subtotal, indent: 2, value: (est, md, day) => _sumCountries(md, day, countries)),
    _RRow('', _RKind.spacer),
  ];
}

List<_RRow> _buildHierarchyRows() {
  return [
    _RRow('PHILIPPINE RESIDENTS', _RKind.topCategory),
    _RRow('FILIPINO NATIONALITY', _RKind.dataLeaf, indent: 1,
        value: (est, md, day) => _res(md, day, 'philippine_resident_filipino')),
    _RRow('FOREIGN NATIONALITY', _RKind.dataLeaf, indent: 1,
        value: (est, md, day) => _res(md, day, 'philippine_resident_foreign')),
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
    _RRow('NON-PHILIPPINE RESIDENCES', _RKind.valueCategory, value: _unlistedForeign),
    _RRow('', _RKind.spacer),
    _RRow('TOTAL NON-PHILIPPINE RESIDENTS', _RKind.total, value: _totalNonPh),
    _RRow('', _RKind.spacer),
    _RRow('OVERSEAS FILIPINOS*', _RKind.valueCategory, value: _overseasFil),
    _RRow('', _RKind.spacer),
    _RRow('GRAND TOTAL GUEST ARRIVALS', _RKind.grandTotal, value: _grandTotal),
    _RRow('Total Philippine Residents', _RKind.total, indent: 1, value: _totalPh),
    _RRow('Total Non-Philippine Residents', _RKind.total, indent: 1, value: _totalNonPh),
    _RRow('Total Overseas Filipinos', _RKind.total, indent: 1, value: _overseasFil),
    _RRow('Total Guest with Unspecified Residence', _RKind.total, indent: 1, value: _unspecifiedGuest),
  ];
}

List<_RRow> _buildIndicatorRows() {
  return [
    _RRow('', _RKind.spacer),
    _RRow('PART II.  Other Indicators', _RKind.sectionTitle),
    _RRow('', _RKind.spacer),
    _RRow('A. DAE2:', _RKind.subsectionTitle),
    _RRow('1. Rooms Occupied', _RKind.indicator, value: _roomsOccupied),
    _RRow('2. Rooms available for the month', _RKind.indicator, value: _roomsAvailable),
    _RRow('3. Total Guest nights', _RKind.indicator, value: _guestNights),
    _RRow('Alternative Submission', _RKind.plainNote),
    _RRow('1. Average Monthly Occupancy Rate', _RKind.indicator,
        value: _occupancyRate, format: (v) => '${v.toStringAsFixed(1)}%'),
    _RRow('2. Average Length of Stay (in Nights)', _RKind.indicator,
        value: _avgLengthOfStay, format: (v) => v.toStringAsFixed(1)),
    _RRow('B. VOLUME PER SEX', _RKind.subsectionTitle),
    _RRow('1. Male', _RKind.indicatorBold),
    _RRow('a. Philippine Residents', _RKind.indicator, indent: 1,
        value: (est, md, day) => _sexCategory(md, day, 'male', 'philippine_residents')),
    _RRow('b. Non-Philippine/Foreign Residents (including unspecified)', _RKind.indicator, indent: 1,
        value: (est, md, day) => _sexCategory(md, day, 'male', 'foreign_residents')),
    _RRow('c. Overseas Filipinos', _RKind.indicator, indent: 1,
        value: (est, md, day) => _sexCategory(md, day, 'male', 'overseas_filipinos')),
    _RRow('d. Others/Unspecified Guest', _RKind.indicator, indent: 1,
        value: (est, md, day) => _sexCategory(md, day, 'male', 'unspecified_guest')),
    _RRow('x. Total', _RKind.indicator, indent: 1, value: _maleTotal),
    _RRow('2. Female', _RKind.indicatorBold),
    _RRow('a. Philippine Residents', _RKind.indicator, indent: 1,
        value: (est, md, day) => _sexCategory(md, day, 'female', 'philippine_residents')),
    _RRow('b. Non-Philippine/Foreign Residents (including unspecified)', _RKind.indicator, indent: 1,
        value: (est, md, day) => _sexCategory(md, day, 'female', 'foreign_residents')),
    _RRow('c. Overseas Filipinos', _RKind.indicator, indent: 1,
        value: (est, md, day) => _sexCategory(md, day, 'female', 'overseas_filipinos')),
    _RRow('d. Others/Unspecified Guest', _RKind.indicator, indent: 1,
        value: (est, md, day) => _sexCategory(md, day, 'female', 'unspecified_guest')),
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
  const base = TextStyle(fontFamily: _Dae.font, color: _Dae.ink, fontSize: _Dae.dataSize);
  switch (k) {
    case _RKind.topCategory:
      return base.copyWith(fontWeight: FontWeight.bold);
    case _RKind.subCategory:
    case _RKind.valueCategory:
    case _RKind.dataLeaf:
    case _RKind.subtotal:
      return base.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic);
    case _RKind.total:
    case _RKind.grandTotal:
      return base.copyWith(fontWeight: FontWeight.bold);
    case _RKind.sectionTitle:
      return base.copyWith(fontWeight: FontWeight.bold, fontSize: _Dae.titleSize);
    case _RKind.subsectionTitle:
      return base.copyWith(fontWeight: FontWeight.bold, fontSize: _Dae.titleSize);
    case _RKind.plainNote:
      return base.copyWith(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, fontSize: _Dae.titleSize);
    case _RKind.indicator:
      return base.copyWith(fontSize: _Dae.indicatorSize);
    case _RKind.indicatorBold:
      return base.copyWith(fontWeight: FontWeight.bold, fontSize: _Dae.indicatorSize);
    case _RKind.footnote:
      return base.copyWith(fontSize: _Dae.indicatorSize, fontStyle: FontStyle.italic, color: Colors.black54);
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
      _cell('COUNTRY OF RESIDENCE', TextStyle(
        fontFamily: _Dae.font,
        fontWeight: FontWeight.bold,
        color: _Dae.ink,
        fontSize: _Dae.dataSize,
      ), _Dae.headerYellow, height: _headerRowHeight, alignLeft: true),
    ];
    for (final c in columns) {
      cells.add(_cell(c.label, TextStyle(
        fontFamily: _Dae.dayFont,
        fontWeight: FontWeight.bold,
        fontStyle: FontStyle.italic,
        color: _Dae.ink,
        fontSize: _Dae.dataSize,
      ), _Dae.headerYellow, height: _headerRowHeight));
    }
    if (showTotalColumn) {
      cells.add(_cell('TOTAL', TextStyle(
        fontFamily: _Dae.font,
        fontWeight: FontWeight.bold,
        color: _Dae.ink,
        fontSize: _Dae.dataSize,
      ), _Dae.headerYellow, height: _headerRowHeight));
    }
    return TableRow(children: cells);
  }

  TableRow _buildDataRow(_RRow r) {
    if (r.kind == _RKind.spacer) {
      final colCount = 1 + columns.length + (showTotalColumn ? 1 : 0);
      return TableRow(
        children: List.generate(colCount, (_) =>
          TableCell(child: SizedBox(height: _spacerRowHeight))),
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
    final isTotalRow = r.kind == _RKind.subtotal || r.kind == _RKind.total || r.kind == _RKind.grandTotal;
    final forceZeroData = isTotalRow || !showTotalColumn;
    for (final c in columns) {
      final v = r.value?.call(est, c.md, c.day) ?? 0;
      rowTotal += v;
      final text = (forceZeroData && v == 0 && r.value != null) ? '0' : _fmt(r, v);
      cells.add(_cell(text, style, bg, height: _dataRowHeight));
    }

    if (showTotalColumn) {
      final totalText = (rowTotal == 0 && r.value != null) ? '0' : _fmt(r, rowTotal);
      cells.add(_cell(totalText, style.copyWith(fontWeight: FontWeight.bold), bg, height: _dataRowHeight));
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
  TabController? _tabController;
  final ScrollController _hScrollCtrl = ScrollController();
  final ScrollController _hScrollCtrlBottom = ScrollController();
  bool _syncingScroll = false;

  double _zoomLevel = 1.0;
  static const double _zoomStep = 0.1;
  static const double _zoomMin = 1.0;
  static const double _zoomMax = 2.0;
  double _unscaledContentHeight = 0;

  void _zoomIn() => setState(() => _zoomLevel = (_zoomLevel + _zoomStep).clamp(_zoomMin, _zoomMax));
  void _zoomOut() => setState(() => _zoomLevel = (_zoomLevel - _zoomStep).clamp(_zoomMin, _zoomMax));
  void _resetZoom() => setState(() => _zoomLevel = 1.0);

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

  void _syncFromContent() {
    if (_syncingScroll) return;
    _syncingScroll = true;
    if (_hScrollCtrlBottom.hasClients && _hScrollCtrlBottom.offset != _hScrollCtrl.offset) {
      _hScrollCtrlBottom.jumpTo(_hScrollCtrl.offset);
    }
    _syncingScroll = false;
  }

  void _syncFromBottom() {
    if (_syncingScroll) return;
    _syncingScroll = true;
    if (_hScrollCtrl.hasClients && _hScrollCtrl.offset != _hScrollCtrlBottom.offset) {
      _hScrollCtrl.jumpTo(_hScrollCtrlBottom.offset);
    }
    _syncingScroll = false;
  }

  final _reportService = ReportService();
  final GlobalKey _contentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _hScrollCtrl.addListener(_syncFromContent);
    _hScrollCtrlBottom.addListener(_syncFromBottom);
    _loadReport();
  }

  @override
  void dispose() {
    _hScrollCtrl.removeListener(_syncFromContent);
    _hScrollCtrlBottom.removeListener(_syncFromBottom);
    _hScrollCtrl.dispose();
    _hScrollCtrlBottom.dispose();
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
      _measureContent();

      if (data.establishments.length > 1) {
        _tabController = TabController(
          length: data.establishments.length,
          vsync: this,
        );
        _tabController!.addListener(() {
          if (!_tabController!.indexIsChanging) _measureContent();
        });
      }
    } catch (e) {
      debugPrint('❌ Report view error: $e');
      if (!mounted) return;
      final code = await classifyError(e);
      setState(() {
        if (code == 503) {
          _error = 'No internet connection. Please check your network and try again.';
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
              onDownloadExcel: _downloading ? null : () => _handleDownload('xlsx'),
              onDownloadPdf: _downloading ? null : () => _handleDownload('pdf'),
              downloading: _downloading,
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

    // Single establishment: no tabs
    if (establishments.length == 1) {
      return _buildEstablishmentView(establishments.first);
    }

    // Multiple establishments: tab bar
    return Column(
      children: [
        Material(
          color: AppColors.backgroundDark,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppColors.primaryCyan,
            unselectedLabelColor: AppColors.textGray,
            indicatorColor: AppColors.primaryCyan,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            tabAlignment: TabAlignment.start,
            tabs: establishments
                .map((e) => Tab(text: e.businessName))
                .toList(),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
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
                  'Region: ${est.region ?? '4-A'}',
                  textAlign: TextAlign.center,
                  style: ts.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.batch.displayPeriod,
                  textAlign: TextAlign.center,
                  style: ts.copyWith(fontStyle: FontStyle.italic, decoration: TextDecoration.underline)
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
                  style: ts.copyWith(fontWeight: FontWeight.bold, fontSize: _Dae.titleSize),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Type of Accommodation — LEFT
          Text('Type of Accommodation', style: ts.copyWith(fontWeight: FontWeight.bold)),
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

    return Stack(
      children: [
        // ── Content area (fills viewport minus pinned scrollbar) ──
        Positioned.fill(
          bottom: 14,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent &&
                  HardwareKeyboard.instance.isControlPressed) {
                final delta = event.scrollDelta.dy > 0 ? -_zoomStep : _zoomStep;
                setState(() =>
                    _zoomLevel = (_zoomLevel + delta).clamp(_zoomMin, _zoomMax));
              }
            },
            child: GestureDetector(
              onScaleUpdate: (details) {
                if (details.pointerCount > 1) {
                  setState(() => _zoomLevel =
                      (_zoomLevel * details.scale).clamp(_zoomMin, _zoomMax));
                }
              },
              child: RawScrollbar(
                thumbVisibility: true,
                thumbColor: Colors.blue,
                trackColor: Colors.blue.withOpacity(0.12),
                trackBorderColor: Colors.blue.withOpacity(0.3),
                radius: const Radius.circular(6),
                thickness: 10,
                child: SingleChildScrollView(
                  primary: true,
                  scrollDirection: Axis.vertical,
                  child: SizedBox(
                    height: _unscaledContentHeight > 0
                        ? (_unscaledContentHeight + 20) * _zoomLevel
                        : null,
                    child: SingleChildScrollView(
                      controller: _hScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20, right: 20),
                        child: SizedBox(
                          width: (tableWidth + 20) * _zoomLevel,
                          child: Transform.scale(
                            scale: _zoomLevel,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              key: _contentKey,
                              width: tableWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                      width: tableWidth,
                                      child: _buildFormHeader(est)),
                                  _buildReportTable(est),
                                  SizedBox(
                                      width: tableWidth,
                                      child: _buildFooter()),
                                ],
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
        ),
        // ── Pinned horizontal scrollbar at viewport bottom ──
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 14,
          child: Container(
            color: AppColors.cardBackground,
            child: RawScrollbar(
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
                child: SizedBox(
                  width: (tableWidth + 20) * _zoomLevel,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ],
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
        final seriesMonthWidth = _dayColWidth;
        final seriesTotalWidth = seriesMonthWidth * 0.9;
        return _labelColWidth + dayColCount * seriesMonthWidth + seriesTotalWidth;
      default:
        dayColCount = 0;
        showTotal = false;
    }
    return _labelColWidth + dayColCount * _dayColWidth + (showTotal ? _totalColWidth : 0);
  }

  Widget _buildFooter() {
    final isDaily = widget.batch.reportVariant == 'daily';
    final ts = const TextStyle(fontFamily: _Dae.font, fontSize: 10, color: _Dae.ink);

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
              style: TextStyle(fontFamily: _Dae.font, fontSize: 10, color: _Dae.ink),
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
              Text('Prepared by:        ____________________________________', style: ts),
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
            style: TextStyle(fontFamily: _Dae.font, color: Colors.black54, fontSize: 12),
          ),
        ),
      );
    }

    switch (widget.batch.reportVariant) {
      case 'daily':
        final year = widget.batch.periodYear;
        final month = widget.batch.periodMonths.first;
        final daysInMonth = DateTime(year, month + 1, 0).day;
        final cols = [for (int d = 1; d <= daysInMonth; d++) _ColumnSpec('$d', md!, '$d')];
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
          '', 'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
          'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
        ];
        final series = est.seriesData ?? const <MonthSeriesEntry>[];
        final cols = [for (final s in series) _ColumnSpec(monthNames[s.month], s.data, '0')];
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
          child: Text('Unknown variant', style: TextStyle(fontFamily: _Dae.font)),
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
    required this.downloading,
    required this.zoomLevel,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
  });

  final ReportBatch batch;
  final VoidCallback onClose;
  final VoidCallback? onDownloadExcel;
  final VoidCallback? onDownloadPdf;
  final bool downloading;
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
              'DAE \u2014 ${batch.variantLabel}',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 5 : 7, vertical: 2),
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
            child: Icon(Icons.remove, color: AppColors.textGray, size: btnIconSize),
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
            child: Icon(Icons.add, color: AppColors.textGray, size: btnIconSize),
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
        padding: EdgeInsets.fromLTRB(horizontalPad, verticalPad, horizontalPad, verticalPad),
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
            Row(
              children: [
                downloadButtons,
                const Spacer(),
                zoomControls,
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPad, verticalPad, horizontalPad, verticalPad),
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
              horizontal: compact ? 8 : 14, vertical: compact ? 5 : 8),
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
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