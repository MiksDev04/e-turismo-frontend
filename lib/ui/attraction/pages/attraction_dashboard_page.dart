// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;
import '../../../core/constants/app_colors.dart';
import '../../../core/services/offline_service.dart';
import '../../shared/layouts/attraction_layout.dart';
import '../../../api/attraction_dashboard_api.dart';
import '../../../core/services/session_service.dart';

const _attractionTypeLabels = {
  'ecotourism': 'Ecotourism',
  'natural_attractions': 'Natural Attractions',
  'cultural': 'Cultural',
  'religious': 'Religious',
  'historical_heritage_sites': 'Historical Heritage Sites',
  'agri_tourism': 'Agri-Tourism',
  'farm_tourism_sites': 'Farm Tourism Sites',
};

String _displayTypeLabel(String raw) {
  final normalised = raw.trim();
  if (normalised.isEmpty) return raw;
  final mapped = _attractionTypeLabels[normalised];
  if (mapped != null) return mapped;
  return normalised
      .toLowerCase()
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

String _displayAttractionTypes(List<String>? values) {
  final types =
      values?.where((value) => value.trim().isNotEmpty).toList() ?? [];
  if (types.isEmpty) return '—';
  return types.map(_displayTypeLabel).join(', ');
}

// ─── Attraction Dashboard Page ────────────────────────────────────────────────

class AttractionDashboardPage extends StatefulWidget {
  const AttractionDashboardPage({super.key});

  @override
  State<AttractionDashboardPage> createState() =>
      _AttractionDashboardPageState();
}

class _AttractionDashboardPageState extends State<AttractionDashboardPage> {
  final _api = AttractionDashboardApi();

  // Attraction info
  String? _attractionId;
  String _attractionName = '';
  List<String> _attractionTypes = [];
  String _address = '';

  // ── Filter state ──────────────────────────────────────────────────────────

  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  int _trendYear1 = DateTime.now().year - 1;
  int _trendYear2 = DateTime.now().year;

  // ── Data state ────────────────────────────────────────────────────────────

  AttractionDashboardData? _dashData;
  Map<int, List<MonthlyCount>> _trendData = {};
  bool _loadingDash = true;
  bool _loadingTrend = true;
  bool _exporting = false;
  String? _dashError;

  // ── Connectivity state ────────────────────────────────────────────────────
  // Attraction accounts are online-only, so the strip just warns the user.
  // When connectivity returns we silently reload the data.

  bool _isOffline = false;
  StreamSubscription<bool>? _connectivitySub;
  Timer? _connectivityDebounce;
  bool _isReconnectReloading = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _isOffline = !ConnectivityService.instance.isOnline;
    _subscribeToConnectivity();

    _initFromSession();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _connectivityDebounce?.cancel();
    super.dispose();
  }

  // ── Connectivity subscription ─────────────────────────────────────────────

  void _subscribeToConnectivity() {
    _connectivitySub =
        ConnectivityService.instance.onConnectivityChanged.listen((isOnline) {
      if (!mounted) return;

      if (isOnline && _isOffline) {
        setState(() => _isOffline = false);
        _connectivityDebounce?.cancel();
        _connectivityDebounce = Timer(const Duration(seconds: 2), () {
          if (mounted) _reloadAll();
        });
      } else if (!isOnline && !_isOffline) {
        _connectivityDebounce?.cancel();
        setState(() => _isOffline = true);
      }
    });
  }

  // ── Init & data loading ───────────────────────────────────────────────────

  Future<void> _initFromSession() async {
    await _refreshAttractionContext(
      preferOnline: ConnectivityService.instance.isOnline,
    );

    if (!mounted) return;

    final futures = <Future>[];
    if (_loadingDash) futures.add(_loadDashboard());
    if (_loadingTrend) futures.add(_loadTrend());
    if (futures.isNotEmpty) await Future.wait(futures);
  }

  Future<void> _reloadAll() async {
    if (!mounted || _isReconnectReloading) return;
    _isReconnectReloading = true;
    try {
      if (_attractionId == null) {
        await _initFromSession();
      } else {
        await Future.wait([_loadDashboard(), _loadTrend()]);
      }
    } finally {
      if (mounted) setState(() => _isReconnectReloading = false);
    }
  }

  Future<void> _refreshAttractionContext({bool preferOnline = false}) async {
    final session =
        SessionService.instance.current ??
        await SessionService.instance.loadAndCache();

    final resolvedId =
        await _api.resolveAttractionId(preferOnline: preferOnline) ??
        session?.attractionId;

    if (!mounted) return;
    setState(() {
      _attractionId = resolvedId;
      _attractionName = session?.attractionName ?? '';
      _attractionTypes = session?.attractionType ?? const [];
      _address = '${session?.street ?? ''}, ${session?.barangay ?? ''}';
    });

    if (_attractionId != null) {
      try {
        final details = await _api.fetchAttractionDetails(
          preferOnline: preferOnline,
        );
        if (!mounted) return;
        setState(() {
          if (details.name.isNotEmpty) _attractionName = details.name;
          if (details.types.isNotEmpty) _attractionTypes = details.types;
          _address = '${details.street}, ${details.barangay}';
        });
      } catch (_) {
        // Keep defaults if the lookup fails.
      }
    }
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;
    setState(() {
      _loadingDash = true;
      _dashError = null;
    });
    try {
      if (_attractionId == null) throw Exception('Attraction account not found.');
      final data = await _api.fetchDashboardData(
        attractionId: _attractionId!,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (mounted) setState(() => _dashData = data);
    } catch (e) {
      if (mounted) setState(() => _dashError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingDash = false);
    }
  }

  Future<void> _loadTrend() async {
    if (!mounted) return;
    setState(() => _loadingTrend = true);
    try {
      if (_attractionId == null) throw Exception('Attraction account not found.');
      final data = await _api.fetchYearlyComparison(
        attractionId: _attractionId!,
        years: [_trendYear1, _trendYear2],
      );
      if (mounted) setState(() => _trendData = data);
    } catch (_) {
      // Non-critical; silently fail.
    } finally {
      if (mounted) setState(() => _loadingTrend = false);
    }
  }

  // ── Exports ───────────────────────────────────────────────────────────────

  Future<Directory> _exportDirectory() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getTemporaryDirectory();
  }

  String _exportLabel() {
    return _selectedMonth == 0
        ? '$_selectedYear'
        : '${_monthShort(_selectedMonth)}_$_selectedYear';
  }

  String _pdfSafe(String s) => s
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2014', '-');

  String _csvCell(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  // ── CSV Export ────────────────────────────────────────────────────────────

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final d = _dashData;
      if (d == null) return;

      final periodLabel = _selectedMonth == 0
          ? 'Full Year $_selectedYear'
          : '${_monthName(_selectedMonth)} $_selectedYear';
      final typesText = _displayAttractionTypes(_attractionTypes);

      final buf = StringBuffer();

      buf.writeln('Attraction,${_csvCell(_attractionName)}');
      buf.writeln('Attraction Type,${_csvCell(typesText)}');
      buf.writeln('Address,${_csvCell(_address)}');
      buf.writeln('Period,${_csvCell(periodLabel)}');
      buf.writeln();

      buf.writeln('SUMMARY');
      buf.writeln('Metric,Value');
      buf.writeln(
        'Visitors This Month/Period,${d.stats.guestsThisMonth}',
      );
      buf.writeln('Visitors Today,${d.stats.visitorsToday}');
      buf.writeln('Visitors This Year,${d.stats.guestsThisYear}');
      buf.writeln(
        'Avg. Visitors per Day,${d.stats.avgTouristsPerDay.toStringAsFixed(1)}',
      );
      buf.writeln();

      buf.writeln('GENDER DISTRIBUTION');
      buf.writeln('Gender,Count,Percentage');
      final g = d.genderDistribution;
      buf.writeln(
        'Male,${g.male},${(g.maleRatio * 100).toStringAsFixed(1)}%',
      );
      buf.writeln(
        'Female,${g.female},${(g.femaleRatio * 100).toStringAsFixed(1)}%',
      );
      buf.writeln(
        'Other,${g.other},${(g.otherRatio * 100).toStringAsFixed(1)}%',
      );
      buf.writeln();

      buf.writeln('TOP COUNTRIES');
      buf.writeln('Country,Guests');
      for (final c in d.topCountries) {
        buf.writeln('${_csvCell(c.country)},${c.count}');
      }
      buf.writeln();

      buf.writeln('TOP PROVINCES');
      buf.writeln('Province,Guests');
      for (final p in d.provinces) {
        buf.writeln('${_csvCell(p.province)},${p.count}');
      }
      buf.writeln();

      buf.writeln('TOP CITIES / MUNICIPALITIES');
      buf.writeln('City / Municipality,Guests');
      for (final c in d.cities) {
        buf.writeln('${_csvCell(c.cityMunicipality)},${c.count}');
      }
      buf.writeln();

      final y1Data =
          _trendData[_trendYear1] ??
          List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));
      final y2Data =
          _trendData[_trendYear2] ??
          List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));

      buf.writeln('TOURIST TREND – $_trendYear1 vs $_trendYear2');
      buf.writeln('Month,$_trendYear1 Visitors,$_trendYear2 Visitors');
      for (int i = 0; i < 12; i++) {
        final y1Count = i < y1Data.length ? y1Data[i].count : 0;
        final y2Count = i < y2Data.length ? y2Data[i].count : 0;
        buf.writeln('${_monthName(i + 1)},$y1Count,$y2Count');
      }

      final labelFile = _exportLabel();
      final fileName = 'attraction_dashboard_$labelFile.csv';
      final bytes = utf8.encode('\uFEFF${buf.toString()}');

      if (kIsWeb) {
        await saveFileToDownloads(fileName, bytes);
        if (!mounted) return;
        _showSnack('CSV downloaded: $fileName');
      } else {
        final dir = await _exportDirectory();
        final file = File(p.join(dir.path, fileName));
        await file.writeAsString('\uFEFF${buf.toString()}', flush: true);

        final result = await OpenFile.open(file.path);
        if (!mounted) return;
        if (result.type != ResultType.done) {
          _showSnack('CSV saved to ${file.path}. ${result.message}');
        } else {
          _showSnack('CSV exported to ${file.path}');
        }
      }
    } catch (e) {
      _showSnack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── PDF Export ────────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final d = _dashData;
      if (d == null) return;

      final doc = pw.Document();
      final label = _selectedMonth == 0
          ? 'Full Year $_selectedYear'
          : '${_monthName(_selectedMonth)} $_selectedYear';
      final typesText = _displayAttractionTypes(_attractionTypes);

      final y1Data =
          _trendData[_trendYear1] ??
          List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));
      final y2Data =
          _trendData[_trendYear2] ??
          List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _attractionName,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Attraction Type: $typesText',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              ),
              pw.Text(
                _address,
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              ),
              pw.Text(
                _pdfSafe('Dashboard Report – $label'),
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Divider(),
            ],
          ),
          build: (_) => [
            pw.Text(
              'Summary',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Metric', 'Value'],
              data: [
                [
                  'Visitors This Month/Period',
                  '${d.stats.guestsThisMonth}',
                ],
                ['Visitors Today', '${d.stats.visitorsToday}'],
                ['Visitors This Year', '${d.stats.guestsThisYear}'],
                [
                  'Avg. Visitors per Day',
                  d.stats.avgTouristsPerDay.toStringAsFixed(1),
                ],
              ],
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Gender Distribution',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Gender', 'Count', 'Percentage'],
              data: [
                [
                  'Male',
                  '${d.genderDistribution.male}',
                  '${(d.genderDistribution.maleRatio * 100).toStringAsFixed(1)}%',
                ],
                [
                  'Female',
                  '${d.genderDistribution.female}',
                  '${(d.genderDistribution.femaleRatio * 100).toStringAsFixed(1)}%',
                ],
                [
                  'Other',
                  '${d.genderDistribution.other}',
                  '${(d.genderDistribution.otherRatio * 100).toStringAsFixed(1)}%',
                ],
              ],
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            pw.Text(
              'Top Countries',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Country', 'Guests'],
              data: d.topCountries
                  .map((c) => [c.country, '${c.count}'])
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            pw.Text(
              'Top Provinces',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Province', 'Guests'],
              data: d.provinces
                  .map((p) => [p.province, '${p.count}'])
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            pw.Text(
              'Top Cities / Municipalities',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['City / Municipality', 'Guests'],
              data: d.cities
                  .map((c) => [c.cityMunicipality, '${c.count}'])
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
            pw.SizedBox(height: 16),

            pw.Text(
              _pdfSafe('Tourist Trend – $_trendYear1 vs $_trendYear2'),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              _pdfSafe('Monthly visitor arrivals — year-over-year comparison'),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: [
                'Month',
                '$_trendYear1 Visitors',
                '$_trendYear2 Visitors',
              ],
              data: List.generate(12, (i) {
                final y1Count = i < y1Data.length ? y1Data[i].count : 0;
                final y2Count = i < y2Data.length ? y2Data[i].count : 0;
                return [_monthName(i + 1), '$y1Count', '$y2Count'];
              }),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );

      final label2 = _exportLabel();
      final fileName = 'attraction_dashboard_$label2.pdf';
      final pdfBytes = await doc.save();

      if (kIsWeb) {
        await saveFileToDownloads(fileName, pdfBytes);
        if (!mounted) return;
        _showSnack('PDF downloaded: $fileName');
      } else {
        final dir = await _exportDirectory();
        final file = File(p.join(dir.path, fileName));
        await file.writeAsBytes(pdfBytes, flush: true);
        final result = await OpenFile.open(file.path);
        if (!mounted) return;
        if (result.type != ResultType.done) {
          _showSnack('PDF saved to ${file.path}. ${result.message}');
        } else {
          _showSnack('PDF exported to ${file.path}');
        }
      }
    } catch (e) {
      _showSnack('PDF export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Export Modal ──────────────────────────────────────────────────────────

  void _showExportMenu() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.gradientStart,
                        AppColors.gradientEnd,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.upload_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Export Report',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _selectedMonth == 0
                      ? 'Full Year $_selectedYear'
                      : '${_monthName(_selectedMonth)} $_selectedYear',
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                _ExportDialogOption(
                  icon: Icons.table_chart_rounded,
                  color: AppColors.accentGreen,
                  title: 'Export as CSV',
                  subtitle: 'Summary, distribution & trend data',
                  onTap: () {
                    Navigator.pop(dialogCtx);
                    _exportCsv();
                  },
                ),
                const SizedBox(height: 10),
                _ExportDialogOption(
                  icon: Icons.picture_as_pdf_rounded,
                  color: AppColors.accentOrange,
                  title: 'Export as PDF',
                  subtitle: 'Formatted report document',
                  onTap: () {
                    Navigator.pop(dialogCtx);
                    _exportPdf();
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.cardBorder),
                      ),
                    ),
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.textGray,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.accentGreen),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AttractionLayout(
      title: 'Dashboard',
      selectedIndex: 0,
      onNavSelected: (_) {},
      child: Column(
        children: [
          // Offline strip — shown whenever the device has no connectivity.
          if (_isOffline) const _OfflineBanner(),

          // Main scrollable content.
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 980;

                      final isMobile = MediaQuery.of(context).size.width < 600;
                      return Padding(
                        padding: EdgeInsets.all(isMobile ? 16 : 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isNarrow) ...[
                              _AttractionHeader(
                                name: _attractionName,
                                types: _attractionTypes,
                                address: _address,
                              ),
                              const SizedBox(height: 16),
                              _FilterRow(
                                selectedMonth: _selectedMonth,
                                selectedYear: _selectedYear,
                                onMonthChanged: (m) {
                                  setState(() => _selectedMonth = m);
                                  _loadDashboard();
                                },
                                onYearChanged: (y) {
                                  setState(() => _selectedYear = y);
                                  _loadDashboard();
                                },
                                onExport: _exporting ? null : _showExportMenu,
                                isExporting: _exporting,
                              ),
                            ] else ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: _AttractionHeader(
                                      name: _attractionName,
                                      types: _attractionTypes,
                                      address: _address,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  _FilterRow(
                                    selectedMonth: _selectedMonth,
                                    selectedYear: _selectedYear,
                                    onMonthChanged: (m) {
                                      setState(() => _selectedMonth = m);
                                      _loadDashboard();
                                    },
                                    onYearChanged: (y) {
                                      setState(() => _selectedYear = y);
                                      _loadDashboard();
                                    },
                                    onExport:
                                        _exporting ? null : _showExportMenu,
                                    isExporting: _exporting,
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 20),
                            if (_loadingDash)
                              const _LoadingSection(height: 100)
                            else if (_dashError != null)
                              _ErrorSection(message: _dashError!)
                            else ...[
                              _StatCards(
                                stats: _dashData!.stats,
                                selectedMonth: _selectedMonth,
                                selectedYear: _selectedYear,
                              ),
                              const SizedBox(height: 20),
                              _DonutChartsRow(
                                genderDist: _dashData!.genderDistribution,
                                topCountries: _dashData!.topCountries,
                                provinces: _dashData!.provinces,
                                cities: _dashData!.cities,
                              ),
                            ],
                            const SizedBox(height: 20),
                            _TouristTrendCard(
                              trendData: _trendData,
                              year1: _trendYear1,
                              year2: _trendYear2,
                              isLoading: _loadingTrend,
                              onYear1Changed: (y) {
                                setState(() => _trendYear1 = y);
                                _loadTrend();
                              },
                              onYear2Changed: (y) {
                                setState(() => _trendYear2 = y);
                                _loadTrend();
                              },
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (_exporting)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryCyan,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Label helpers ─────────────────────────────────────────────────────────

  static String _monthName(int m) => const [
    '',
    'January', 'February', 'March',      'April',
    'May',     'June',     'July',       'August',
    'September', 'October', 'November',  'December',
  ][m];

  static String _monthShort(int m) => const [
    '',
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][m];
}

// ─── Offline Banner ───────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1A1A2E),
      child: const Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFF8A9BB5), size: 14),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'You\'re offline — data may not be up to date.',
              style: TextStyle(color: Color(0xFF8A9BB5), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Export Dialog Option ─────────────────────────────────────────────────────

class _ExportDialogOption extends StatelessWidget {
  const _ExportDialogOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textGray,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: color.withOpacity(0.7),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Attraction Header ────────────────────────────────────────────────────────

class _AttractionHeader extends StatelessWidget {
  const _AttractionHeader({
    required this.name,
    required this.types,
    required this.address,
  });

  final String name;
  final List<String> types;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? 'Tourist Attraction' : name,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (types.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: types.map((type) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.primaryCyan.withOpacity(0.25),
                  ),
                ),
                child: Text(
                  _displayTypeLabel(type),
                  style: const TextStyle(
                    color: AppColors.primaryCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          )
        else
          const Text(
            'Attraction type unavailable',
            style: TextStyle(color: AppColors.textGray, fontSize: 13),
          ),
        const SizedBox(height: 6),
        Text(
          address.trim().replaceAll(', ,', ','),
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

// ─── Filter Row ───────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.selectedMonth,
    required this.selectedYear,
    required this.onMonthChanged,
    required this.onYearChanged,
    required this.onExport,
    required this.isExporting,
  });

  final int selectedMonth;
  final int selectedYear;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<int> onYearChanged;
  final VoidCallback? onExport;
  final bool isExporting;

  static const _months = [
    (0, 'All Months'),
    (1, 'January'),
    (2, 'February'),
    (3, 'March'),
    (4, 'April'),
    (5, 'May'),
    (6, 'June'),
    (7, 'July'),
    (8, 'August'),
    (9, 'September'),
    (10, 'October'),
    (11, 'November'),
    (12, 'December'),
  ];

  List<int> get _years {
    final now = DateTime.now().year;
    return List.generate(5, (i) => now - i);
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Wrap(
      spacing: isNarrow ? 6 : 10,
      runSpacing: isNarrow ? 6 : 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: isNarrow ? 140 : 170,
          child: _FilterDropdown<int>(
            value: selectedMonth,
            items: _months.map((m) => (m.$1, m.$2)).toList(),
            onChanged: onMonthChanged,
            icon: Icons.calendar_month_rounded,
          ),
        ),
        SizedBox(
          width: isNarrow ? 90 : 110,
          child: _FilterDropdown<int>(
            value: selectedYear,
            items: _years.map((y) => (y, '$y')).toList(),
            onChanged: onYearChanged,
            icon: Icons.event_rounded,
          ),
        ),
        _ExportButton(onTap: onExport, isLoading: isExporting),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.icon,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: AppColors.primaryCyan),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                dropdownColor: AppColors.cardBackground,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textGray,
                  size: 18,
                ),
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 12,
                ),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
                items: items
                    .map(
                      (item) => DropdownMenuItem<T>(
                        value: item.$1,
                        child: Text(item.$2, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onTap, required this.isLoading});

  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            else
              const Icon(Icons.upload_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            const Text(
              'Export',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat Cards ───────────────────────────────────────────────────────────────

class _StatCards extends StatelessWidget {
  const _StatCards({
    required this.stats,
    required this.selectedMonth,
    required this.selectedYear,
  });

  final AttractionStats stats;
  final int selectedMonth;
  final int selectedYear;

  String get _monthLabel => selectedMonth == 0 ? 'This Year' : 'This Month';

  String get _yearSubLabel {
    final currentYear = DateTime.now().year;
    if (selectedYear < currentYear) return 'Full Year $selectedYear';
    const months = [
      '',
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Jan \u2013 ${months[DateTime.now().month]} $selectedYear';
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        icon: Icons.people_alt_rounded,
        iconColor: AppColors.primaryCyan,
        value: '${stats.guestsThisMonth}',
        label: 'Visitors $_monthLabel',
      ),
      _StatCard(
        icon: Icons.today_rounded,
        iconColor: AppColors.accentGreen,
        value: '${stats.visitorsToday}',
        label: 'Visitors Today',
        infoTooltip: 'Recorded visits for today',
      ),
      _StatCard(
        icon: Icons.trending_up_rounded,
        iconColor: AppColors.primaryBlue,
        value: '${stats.guestsThisYear}',
        label: 'Visitors This Year',
        infoTooltip: _yearSubLabel,
      ),
      _StatCard(
        icon: Icons.schedule_rounded,
        iconColor: AppColors.accentOrange,
        value: stats.avgTouristsPerDay.toStringAsFixed(1),
        label: 'Avg. Visitors per Day',
        infoTooltip: 'Visitors this period ÷ days in period',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 14),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 14),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: cards
              .expand(
                (c) => [
                  Expanded(child: c),
                  if (c != cards.last) const SizedBox(width: 14),
                ],
              )
              .toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.infoTooltip,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String? infoTooltip;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;
    return _DashCard(
      child: SizedBox(
        width: double.infinity,
        child: isDesktop
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(icon, color: iconColor, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        value,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (infoTooltip != null) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: infoTooltip!,
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: iconColor, size: 18),
                  const SizedBox(height: 10),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: AppColors.textGray,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (infoTooltip != null) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: infoTooltip!,
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: AppColors.textGray,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Donut Charts Row ─────────────────────────────────────────────────────────

class _DonutChartsRow extends StatelessWidget {
  const _DonutChartsRow({
    required this.genderDist,
    required this.topCountries,
    required this.provinces,
    required this.cities,
  });

  final GenderDistribution genderDist;
  final List<CountryCount> topCountries;
  final List<ProvinceCount> provinces;
  final List<CityCount> cities;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final isMedium = constraints.maxWidth < 900;

        final genderCard = _GenderCard(genderDist: genderDist);
        final countriesCard = _CountriesCard(
          topCountries: topCountries,
          provinces: provinces,
        );
        final citiesCard = _CitiesCard(cities: cities);

        if (isNarrow) {
          return Column(
            children: [
              genderCard,
              const SizedBox(height: 14),
              countriesCard,
              const SizedBox(height: 14),
              citiesCard,
            ],
          );
        } else if (isMedium) {
          return Column(
            children: [
              genderCard,
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: countriesCard),
                  const SizedBox(width: 14),
                  Expanded(child: citiesCard),
                ],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: genderCard),
            const SizedBox(width: 14),
            Expanded(child: countriesCard),
            const SizedBox(width: 14),
            Expanded(child: citiesCard),
          ],
        );
      },
    );
  }
}

// ─── Toggle Card Title ────────────────────────────────────────────────────────

class _ToggleCardTitle extends StatelessWidget {
  const _ToggleCardTitle({
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (int i = 0; i < options.length; i++) {
      if (i > 0) {
        widgets.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '/',
              style: TextStyle(
                color: AppColors.textSubtle,
                fontSize: 12,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        );
      }
      final isSelected = i == selectedIndex;
      widgets.add(
        GestureDetector(
          onTap: () => onChanged(i),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isSelected
                      ? AppColors.primaryCyan
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
            ),
            child: Text(
              options[i],
              style: TextStyle(
                color: isSelected ? AppColors.textWhite : AppColors.textGray,
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: widgets);
  }
}

// ─── Gender Card ──────────────────────────────────────────────────────────────

class _GenderCard extends StatelessWidget {
  const _GenderCard({required this.genderDist});

  final GenderDistribution genderDist;

  @override
  Widget build(BuildContext context) {
    final d = genderDist;
    final isEmpty = d.total == 0;

    final segments = isEmpty
        ? List.generate(
            3,
            (i) => _Segment(
              value: 1 / 3,
              color: const [
                AppColors.chartCyan,
                AppColors.chartPurple,
                AppColors.chartGray,
              ][i],
              isEmpty: true,
            ),
          )
        : [
            _Segment(
              value: d.maleRatio,
              color: AppColors.chartCyan,
              label: 'Male',
              count: d.male,
            ),
            _Segment(
              value: d.femaleRatio,
              color: AppColors.chartPurple,
              label: 'Female',
              count: d.female,
            ),
            _Segment(
              value: d.otherRatio,
              color: AppColors.chartGray,
              label: 'Other',
              count: d.other,
            ),
          ];

    const legend = [
      _LegendItem(label: 'Male', color: AppColors.chartCyan),
      _LegendItem(label: 'Female', color: AppColors.chartPurple),
      _LegendItem(label: 'Other', color: AppColors.chartGray),
    ];

    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(title: 'Gender'),
          if (isEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              'No data for this period',
              style: TextStyle(color: AppColors.textSubtle, fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          _DonutContent(segments: segments, legend: legend),
        ],
      ),
    );
  }
}

// ─── Countries / Provinces Card ───────────────────────────────────────────────

class _CountriesCard extends StatefulWidget {
  const _CountriesCard({
    required this.topCountries,
    required this.provinces,
  });

  final List<CountryCount> topCountries;
  final List<ProvinceCount> provinces;

  @override
  State<_CountriesCard> createState() => _CountriesCardState();
}

class _CountriesCardState extends State<_CountriesCard> {
  int _tab = 0; // 0 = Country, 1 = Province

  static const _countryColors = [
    AppColors.chartGreen,
    AppColors.chartBlue,
    AppColors.chartOrange,
    AppColors.chartPurple,
    AppColors.chartGray,
  ];

  static const _provinceColors = [
    AppColors.chartBlue,
    AppColors.chartGreen,
    AppColors.chartOrange,
    AppColors.chartPurple,
    AppColors.chartCyan,
    AppColors.chartGray,
  ];

  List<Color> get _colors => _tab == 0 ? _countryColors : _provinceColors;

  List<({String label, int count})> get _list => _tab == 0
      ? widget.topCountries
          .map((c) => (label: c.country, count: c.count))
          .toList()
      : widget.provinces
          .map((p) => (label: p.province, count: p.count))
          .toList();

  List<_Segment> get _segments {
    final list = _list;
    if (list.isEmpty) {
      return List.generate(
        5,
        (i) => _Segment(
          value: 0.2,
          color: _colors[i % _colors.length],
          isEmpty: true,
        ),
      );
    }
    final total = list.fold<int>(0, (s, n) => s + n.count);
    return list.asMap().entries.map((e) {
      final ratio = total == 0 ? 1 / list.length : e.value.count / total;
      return _Segment(
        value: ratio,
        color: _colors[e.key % _colors.length],
        label: e.value.label,
        count: e.value.count,
      );
    }).toList();
  }

  List<_LegendItem> get _legend => _list
      .asMap()
      .entries
      .map(
        (e) => _LegendItem(
          label: e.value.label,
          color: _colors[e.key % _colors.length],
        ),
      )
      .toList();

  String? get _emptyHint =>
      _list.isEmpty ? 'No data for this period' : null;

  @override
  Widget build(BuildContext context) {
    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToggleCardTitle(
            options: const ['Country', 'Province'],
            selectedIndex: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          if (_emptyHint != null) ...[
            const SizedBox(height: 6),
            Text(
              _emptyHint!,
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          _DonutContent(
            key: ValueKey(_tab),
            segments: _segments,
            legend: _legend,
          ),
        ],
      ),
    );
  }
}

// ─── Cities / Municipalities Card ─────────────────────────────────────────────

class _CitiesCard extends StatelessWidget {
  const _CitiesCard({required this.cities});

  final List<CityCount> cities;

  static const _colors = [
    AppColors.chartOrange,
    AppColors.chartBlue,
    AppColors.chartGreen,
    AppColors.chartPurple,
    AppColors.chartCyan,
    AppColors.chartGray,
  ];

  @override
  Widget build(BuildContext context) {
    final isEmpty = cities.isEmpty;
    final total = cities.fold<int>(0, (s, c) => s + c.count);

    final segments = isEmpty
        ? List.generate(
            5,
            (i) => _Segment(
              value: 0.2,
              color: _colors[i % _colors.length],
              isEmpty: true,
            ),
          )
        : cities.asMap().entries.map((e) {
            final ratio = total == 0 ? 1 / cities.length : e.value.count / total;
            return _Segment(
              value: ratio,
              color: _colors[e.key % _colors.length],
              label: e.value.cityMunicipality,
              count: e.value.count,
            );
          }).toList();

    final legend = cities
        .asMap()
        .entries
        .map(
          (e) => _LegendItem(
            label: e.value.cityMunicipality,
            color: _colors[e.key % _colors.length],
          ),
        )
        .toList();

    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle(title: 'Cities / Municipalities'),
          if (isEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              'No data for this period',
              style: TextStyle(color: AppColors.textSubtle, fontSize: 11),
            ),
          ],
          const SizedBox(height: 16),
          _DonutContent(segments: segments, legend: legend),
        ],
      ),
    );
  }
}

// ─── Donut Content (chart + legend) ───────────────────────────────────────────

class _DonutContent extends StatelessWidget {
  const _DonutContent({
    super.key,
    required this.segments,
    required this.legend,
  });

  final List<_Segment> segments;
  final List<_LegendItem> legend;

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 600;
    final chartSize = isSmall ? 120.0 : 130.0;

    return Column(
      children: [
        Center(child: _DonutChart(segments: segments, size: chartSize)),
        if (legend.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Legend(items: legend),
        ],
      ],
    );
  }
}

// ─── Tourist Trend Card ───────────────────────────────────────────────────────

class _TouristTrendCard extends StatelessWidget {
  const _TouristTrendCard({
    required this.trendData,
    required this.year1,
    required this.year2,
    required this.isLoading,
    required this.onYear1Changed,
    required this.onYear2Changed,
  });

  final Map<int, List<MonthlyCount>> trendData;
  final int year1;
  final int year2;
  final bool isLoading;
  final ValueChanged<int> onYear1Changed;
  final ValueChanged<int> onYear2Changed;

  List<int> get _availableYears {
    final now = DateTime.now().year;
    return List.generate(8, (i) => now - i);
  }

  @override
  Widget build(BuildContext context) {
    final chartHeight =
        MediaQuery.of(context).size.width < 500 ? 180.0 : 220.0;
    final y1Data =
        trendData[year1] ??
        List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));
    final y2Data =
        trendData[year2] ??
        List.generate(12, (i) => MonthlyCount(month: i + 1, count: 0));

    return _DashCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _CardTitle(title: 'Tourist Trend')),
              _YearPill(
                year: year1,
                color: AppColors.chartPurple,
                years: _availableYears,
                onChanged: onYear1Changed,
              ),
              const SizedBox(width: 8),
              _YearPill(
                year: year2,
                color: AppColors.chartCyan,
                years: _availableYears,
                onChanged: onYear2Changed,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Monthly visitor arrivals — year-over-year comparison',
            style: TextStyle(color: AppColors.textSubtle, fontSize: 11),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            SizedBox(
              height: chartHeight,
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryCyan,
                ),
              ),
            )
          else
            SizedBox(
              height: chartHeight,
              child: _ComparisonBarChart(
                year1: year1,
                year2: year2,
                year1Data: y1Data,
                year2Data: y2Data,
              ),
            ),
        ],
      ),
    );
  }
}

class _YearPill extends StatelessWidget {
  const _YearPill({
    required this.year,
    required this.color,
    required this.years,
    required this.onChanged,
  });

  final int year;
  final Color color;
  final List<int> years;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: year,
          dropdownColor: AppColors.cardBackground,
          icon: Icon(Icons.arrow_drop_down_rounded, color: color, size: 18),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: years
              .map(
                (y) => DropdownMenuItem<int>(value: y, child: Text('$y')),
              )
              .toList(),
        ),
      ),
    );
  }
}

// ─── Comparison Bar Chart ─────────────────────────────────────────────────────

class _ComparisonBarChart extends StatefulWidget {
  const _ComparisonBarChart({
    required this.year1,
    required this.year2,
    required this.year1Data,
    required this.year2Data,
  });

  final int year1;
  final int year2;
  final List<MonthlyCount> year1Data;
  final List<MonthlyCount> year2Data;

  @override
  State<_ComparisonBarChart> createState() => _ComparisonBarChartState();
}

class _ComparisonBarChartState extends State<_ComparisonBarChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _hoveredIsYear2 = false;
  int _hoveredMonth = -1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..forward();
  }

  @override
  void didUpdateWidget(_ComparisonBarChart old) {
    super.didUpdateWidget(old);
    if (old.year1 != widget.year1 || old.year2 != widget.year2) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (event) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              _detectHover(
                box.globalToLocal(event.position),
                constraints.biggest,
              );
            }
          },
          onExit: (_) => setState(() => _hoveredMonth = -1),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              painter: _ComparisonBarPainter(
                year1: widget.year1,
                year2: widget.year2,
                year1Data: widget.year1Data,
                year2Data: widget.year2Data,
                animValue: _ctrl.value,
                hoveredMonth: _hoveredMonth,
                hoveredIsYear2: _hoveredIsYear2,
              ),
              size: constraints.biggest,
            ),
          ),
        );
      },
    );
  }

  void _detectHover(Offset pos, Size size) {
    const leftPad = 42.0;
    const bottomPad = 36.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad;

    if (pos.dy < 0 || pos.dy > chartH) {
      if (_hoveredMonth != -1) setState(() => _hoveredMonth = -1);
      return;
    }

    final groupW = chartW / 12;
    final barW = groupW * 0.30;
    const gap = 2.0;

    final allVals = [
      ...widget.year1Data.map((d) => d.count),
      ...widget.year2Data.map((d) => d.count),
    ];
    final maxVal = allVals.isEmpty ? 1 : allVals.reduce(math.max);
    final effectiveMax = (maxVal * 1.2).ceilToDouble();

    for (int i = 0; i < 12; i++) {
      final groupX = leftPad + i * groupW + groupW / 2 - barW - gap / 2;

      final x1 = groupX;
      final h1 = (widget.year1Data[i].count / effectiveMax) *
          chartH *
          _ctrl.value;
      if (pos.dx >= x1 && pos.dx <= x1 + barW && pos.dy >= chartH - h1) {
        if (_hoveredMonth != i || _hoveredIsYear2) {
          setState(() {
            _hoveredMonth = i;
            _hoveredIsYear2 = false;
          });
        }
        return;
      }

      final x2 = groupX + barW + gap;
      final h2 = (widget.year2Data[i].count / effectiveMax) *
          chartH *
          _ctrl.value;
      if (pos.dx >= x2 && pos.dx <= x2 + barW && pos.dy >= chartH - h2) {
        if (_hoveredMonth != i || !_hoveredIsYear2) {
          setState(() {
            _hoveredMonth = i;
            _hoveredIsYear2 = true;
          });
        }
        return;
      }
    }

    if (_hoveredMonth != -1) setState(() => _hoveredMonth = -1);
  }
}

class _ComparisonBarPainter extends CustomPainter {
  const _ComparisonBarPainter({
    required this.year1,
    required this.year2,
    required this.year1Data,
    required this.year2Data,
    required this.animValue,
    required this.hoveredMonth,
    required this.hoveredIsYear2,
  });

  final int year1;
  final int year2;
  final List<MonthlyCount> year1Data;
  final List<MonthlyCount> year2Data;
  final double animValue;
  final int hoveredMonth;
  final bool hoveredIsYear2;

  static const _monthLabels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _color1 = AppColors.chartPurple;
  static const _color2 = AppColors.chartCyan;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 42.0;
    const bottomPad = 36.0;
    final chartW = size.width - leftPad;
    final chartH = size.height - bottomPad;

    final allVals = [
      ...year1Data.map((d) => d.count),
      ...year2Data.map((d) => d.count),
    ];
    final maxVal = allVals.isEmpty ? 0 : allVals.reduce(math.max);
    final effectiveMax = maxVal == 0 ? 10.0 : (maxVal * 1.25).ceilToDouble();

    final gridPaint = Paint()
      ..color = AppColors.cardBorder
      ..strokeWidth = 0.5;
    final labelStyle = TextStyle(
      color: AppColors.textSubtle,
      fontSize: size.width < 400 ? 8.5 : 10,
    );

    const ySteps = 5;
    for (int i = 0; i <= ySteps; i++) {
      final val = (effectiveMax * i / ySteps).round();
      final y = chartH - (val / effectiveMax) * chartH;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      _drawText(canvas, '$val', Offset(0, y - 6), labelStyle, leftPad - 4);
    }

    final groupW = chartW / 12;
    const gap = 2.0;
    final barW = groupW * 0.30;

    for (int i = 0; i < 12; i++) {
      final groupX = leftPad + i * groupW + groupW / 2 - barW - gap / 2;

      final v1 = year1Data[i].count;
      final h1 = (v1 / effectiveMax) * chartH * animValue;
      final isHov1 = hoveredMonth == i && !hoveredIsYear2;

      if (h1 > 0) {
        final rect1 = Rect.fromLTWH(groupX, chartH - h1, barW, h1);
        final paint1 = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              isHov1 ? _color1 : _color1.withOpacity(0.9),
              _color1.withOpacity(isHov1 ? 0.8 : 0.4),
            ],
          ).createShader(rect1);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect1,
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          paint1,
        );
      }

      final v2 = year2Data[i].count;
      final h2 = (v2 / effectiveMax) * chartH * animValue;
      final isHov2 = hoveredMonth == i && hoveredIsYear2;
      final x2 = groupX + barW + gap;

      if (h2 > 0) {
        final rect2 = Rect.fromLTWH(x2, chartH - h2, barW, h2);
        final paint2 = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              isHov2 ? _color2 : _color2.withOpacity(0.9),
              _color2.withOpacity(isHov2 ? 0.8 : 0.4),
            ],
          ).createShader(rect2);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect2,
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          paint2,
        );
      }

      if (hoveredMonth == i) {
        final isY2 = hoveredIsYear2;
        final hov = isY2 ? h2 : h1;
        final hovVal = isY2 ? v2 : v1;
        final hovYear = isY2 ? year2 : year1;
        final hovX = isY2 ? x2 : groupX;
        final hovColor = isY2 ? _color2 : _color1;
        _drawTooltip(
          canvas,
          '$hovYear: $hovVal visitors',
          hovColor,
          Offset(hovX + barW / 2, chartH - hov - 8),
          size.width,
        );
      }

      final labelX = leftPad + i * groupW + groupW / 2 - 10;
      _drawText(
        canvas,
        _monthLabels[i],
        Offset(labelX, chartH + 8),
        labelStyle,
        groupW,
      );
    }

    _drawLegend(canvas, size, chartH + 22);
  }

  void _drawLegend(Canvas canvas, Size size, double y) {
    const dotR = 5.0;
    const spacing = 12.0;

    final style = TextStyle(
      color: AppColors.textGray,
      fontSize: size.width < 400 ? 9 : 11,
    );

    final p1 = Paint()..color = _color1;
    canvas.drawCircle(Offset(size.width / 2 - 60, y + dotR), dotR, p1);
    _drawText(
      canvas,
      '$year1',
      Offset(size.width / 2 - 60 + dotR * 2 + 2, y),
      style,
      60,
    );

    final p2 = Paint()..color = _color2;
    canvas.drawCircle(
      Offset(size.width / 2 + spacing + 20, y + dotR),
      dotR,
      p2,
    );
    _drawText(
      canvas,
      '$year2',
      Offset(size.width / 2 + spacing + 20 + dotR * 2 + 2, y),
      style,
      60,
    );
  }

  void _drawTooltip(
    Canvas canvas,
    String text,
    Color color,
    Offset anchor,
    double maxWidth,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final tw = tp.width + 14;
    final th = tp.height + 8;
    var tx = anchor.dx - tw / 2;
    final ty = anchor.dy - th - 4;

    tx = tx.clamp(0, maxWidth - tw);

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(tx, ty, tw, th),
      const Radius.circular(5),
    );
    canvas.drawRRect(bgRect, Paint()..color = const Color(0xFF1E293B));
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = color.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    tp.paint(canvas, Offset(tx + 7, ty + 4));
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style,
    double maxW,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ComparisonBarPainter old) =>
      old.animValue != animValue ||
      old.hoveredMonth != hoveredMonth ||
      old.hoveredIsYear2 != hoveredIsYear2 ||
      old.year1 != year1 ||
      old.year2 != year2;
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _DashCard extends StatelessWidget {
  const _DashCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 500;
    return Container(
      padding: EdgeInsets.all(isSmall ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 500;
    return Text(
      title,
      style: TextStyle(
        color: AppColors.textWhite,
        fontSize: isSmall ? 12 : 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ─── Legend ───────────────────────────────────────────────────────────────────

class _LegendItem {
  const _LegendItem({required this.label, required this.color});

  final String label;
  final Color color;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 500;
    return Wrap(
      spacing: isSmall ? 8 : 12,
      runSpacing: 6,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: item.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              item.label,
              style: TextStyle(
                color: AppColors.textGray,
                fontSize: isSmall ? 10 : 11,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ─── Donut Chart ──────────────────────────────────────────────────────────────

class _Segment {
  const _Segment({
    required this.value,
    required this.color,
    this.label,
    this.percentage,
    this.count,
    this.isEmpty = false,
  });

  final double value;
  final Color color;
  final String? label;
  final String? percentage;
  final int? count;
  final bool isEmpty;
}

class _DonutChart extends StatefulWidget {
  const _DonutChart({required this.segments, required this.size});

  final List<_Segment> segments;
  final double size;

  @override
  State<_DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<_DonutChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  int _hoveredIdx = -1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..forward();
  }

  @override
  void didUpdateWidget(_DonutChart old) {
    super.didUpdateWidget(old);
    _ctrl
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _checkHover(Offset pos, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = pos.dx - center.dx;
    final dy = pos.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final strokeW = size.width * 0.17;
    final inner = size.width / 2 - strokeW;
    final outer = size.width / 2;

    if (dist < inner || dist > outer) {
      if (_hoveredIdx != -1) setState(() => _hoveredIdx = -1);
      return;
    }

    final angle = math.atan2(dy, dx);
    final startAngle = (angle + math.pi / 2 + math.pi * 2) % (math.pi * 2);

    double acc = 0;
    for (int i = 0; i < widget.segments.length; i++) {
      final seg = widget.segments[i].value * math.pi * 2;
      if (startAngle >= acc && startAngle <= acc + seg) {
        if (_hoveredIdx != i) setState(() => _hoveredIdx = i);
        return;
      }
      acc += seg;
    }

    if (_hoveredIdx != -1) setState(() => _hoveredIdx = -1);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          _checkHover(
            box.globalToLocal(e.position),
            Size(widget.size, widget.size),
          );
        }
      },
      onExit: (_) => setState(() => _hoveredIdx = -1),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Opacity(
          opacity: _ctrl.value,
          child: Transform.scale(
            scale: 0.95 + _ctrl.value * 0.05,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    painter: _DonutPainter(
                      segments: widget.segments,
                      animValue: _ctrl.value,
                      hoveredIdx: _hoveredIdx,
                    ),
                    size: Size(widget.size, widget.size),
                  ),
                  if (_hoveredIdx != -1 &&
                      widget.segments[_hoveredIdx].label != null &&
                      !widget.segments[_hoveredIdx].isEmpty)
                    _DonutTooltip(segment: widget.segments[_hoveredIdx]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutTooltip extends StatelessWidget {
  const _DonutTooltip({required this.segment});

  final _Segment segment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            segment.label!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            segment.count != null
                ? '${segment.count} visitors'
                : segment.percentage!,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.segments,
    required this.animValue,
    required this.hoveredIdx,
  });

  final List<_Segment> segments;
  final double animValue;
  final int hoveredIdx;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeW = size.width * 0.17;
    final rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeW / 2,
    );

    double startAngle = -math.pi / 2;
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final sweep = seg.value * 2 * math.pi * animValue;
      final isHov = hoveredIdx == i;
      final currentStroke = isHov ? strokeW + 5 : strokeW;
      final color = seg.isEmpty
          ? seg.color.withOpacity(0.15)
          : (isHov ? seg.color : seg.color.withOpacity(0.85));
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = currentStroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweep - 0.04, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.animValue != animValue ||
      old.hoveredIdx != hoveredIdx;
}

// ─── Loading / Error States ───────────────────────────────────────────────────

class _LoadingSection extends StatelessWidget {
  const _LoadingSection({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.primaryCyan),
      ),
    );
  }
}

class _ErrorSection extends StatelessWidget {
  const _ErrorSection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not load data: $message',
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
