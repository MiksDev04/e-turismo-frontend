import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/api/attraction_visit_record_api.dart';
import '../../shared/layouts/attraction_layout.dart';
import '../../shared/widgets/paginator.dart';
import '../../../router/app_routes.dart';


String _fmtDate(DateTime dt) {
  return "${dt.year.toString().padLeft(4,'0')}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}";
}

String _fmtDateTime(DateTime? dt) {
  if (dt == null) return '-';
  return "${_fmtDate(dt)} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
}

String _locationDisplay(VisitRecord r) {
  if (r.isForeign) {
    if (r.country != null && r.country!.isNotEmpty) return r.country!;
    return 'Unknown';
  }
  final parts = <String>[];
  if (r.province != null && r.province!.isNotEmpty) parts.add(r.province!);
  if (r.cityMunicipality != null && r.cityMunicipality!.isNotEmpty) parts.add(r.cityMunicipality!);
  if (parts.isEmpty) return '-';
  return parts.join(', ');
}

String _nationalityLabel(VisitRecord r) {
  if (r.nationality != null && r.nationality!.isNotEmpty) return r.nationality!;
  return r.isForeign ? 'Foreign' : 'Filipino';
}

class VisitRecordDetailDialog extends StatelessWidget {
  const VisitRecordDetailDialog({super.key, required this.record});
  final VisitRecord record;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.backgroundMid.withOpacity(0.5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                border: const Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Visit Record Details', style: TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w600)),
                  GestureDetector(onTap: () => Navigator.of(context).pop(), child: const Icon(Icons.close_rounded, color: AppColors.textGray, size: 20)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: _DetailGrid(record: record),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(backgroundColor: AppColors.primaryCyan.withOpacity(0.1), foregroundColor: AppColors.primaryCyan, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text('Close', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.record});
  final VisitRecord record;

  @override
  Widget build(BuildContext context) {
    final rows = <_DetailRow>[
      _DetailRow('Visit Date', _fmtDate(record.visitDate)),
      _DetailRow('Guest Count', record.guestCount.toString()),
      _DetailRow('Male Count', record.maleCount?.toString() ?? '-'),
      _DetailRow('Female Count', record.femaleCount?.toString() ?? '-'),
      _DetailRow('Nationality', _nationalityLabel(record)),
    ];
    if (record.isForeign) {
      rows.add(_DetailRow('Country', record.country ?? '-'));
      rows.add(_DetailRow('Province', '-'));
      rows.add(_DetailRow('City / Municipality', '-'));
    } else {
      rows.add(_DetailRow('Country', '-'));
      rows.add(_DetailRow('Province', record.province ?? '-'));
      rows.add(_DetailRow('City / Municipality', record.cityMunicipality ?? '-'));
    }
    rows.add(_DetailRow('Created At', _fmtDateTime(record.createdAt)));
    rows.add(_DetailRow('Updated At', _fmtDateTime(record.updatedAt)));

    return Column(
      children: List.generate(rows.length, (i) {
        final r = rows[i];
        return Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.cardBorder))),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              SizedBox(width: 140, child: Text(r.label, style: const TextStyle(color: AppColors.textGray, fontSize: 12))),
              Expanded(child: Text(r.value, style: const TextStyle(color: AppColors.textWhite, fontSize: 12.5, fontWeight: FontWeight.w500))),
            ],
          ),
        );
      }),
    );
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;
}

class AttractionVisitRecordsPage extends StatefulWidget {
  const AttractionVisitRecordsPage({super.key});
  @override
  State<AttractionVisitRecordsPage> createState() => _AttractionVisitRecordsPageState();
}

class _AttractionVisitRecordsPageState extends State<AttractionVisitRecordsPage> {
  final _api = AttractionVisitRecordApi();
  final _searchCtrl = TextEditingController();

  List<VisitRecord> _records = [];
  bool _isLoading = true;
  String? _loadError;

  int _currentPage = 0;
  int _pageSize = 10;
  int _totalPages = 0;
  int _totalItems = 0;

  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _originFilter = 'all';

  static const List<int> _pageSizeOptions = [10, 20, 30];
  static const List<String> _originOptions = ['all', 'domestic', 'international'];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final result = await _api.fetchVisitRecords(
        page: _currentPage + 1,
        pageSize: _pageSize,
        dateFrom: _dateFrom?.toIso8601String().split('T').first,
        dateTo: _dateTo?.toIso8601String().split('T').first,
        origin: _originFilter,
      );

      if (!mounted) return;
      if (result.isSuccess) {
        final data = result.data!;
        setState(() {
          _records = data.data;
          _totalPages = data.pageCount;
          _totalItems = data.totalCount;
        });
      } else {
        setState(() => _loadError = result.error);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Failed to load records: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _dateFrom != null && _dateTo != null
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : null,
      builder: (ctx, child) => Theme(
        data: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF3B82F6),
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF111827),
          ),
          dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _dateFrom = picked.start;
      _dateTo = picked.end;
      _currentPage = 0;
    });
    _loadRecords();
  }

  void _clearDateRange() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _currentPage = 0;
    });
    _searchCtrl.clear();
    _loadRecords();
  }

  List<VisitRecord> get _filteredRecords {
    final query = _searchCtrl.text.toLowerCase().trim();
    if (query.isEmpty) return _records;
    return _records.where((r) {
      return r.guestCount.toString().contains(query) ||
          (r.country?.toLowerCase().contains(query) ?? false) ||
          (r.province?.toLowerCase().contains(query) ?? false) ||
          (r.cityMunicipality?.toLowerCase().contains(query) ?? false) ||
          _nationalityLabel(r).toLowerCase().contains(query) ||
          _fmtDate(r.visitDate).contains(query);
    }).toList();
  }

  Future<void> _showDetail(VisitRecord record) async {
    final detail = await _api.fetchVisitRecordById(record.id);
    if (!mounted) return;
    VisitRecord displayRecord = record;
    if (detail.isSuccess && detail.data != null) {
      displayRecord = detail.data!;
    }
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (_) => VisitRecordDetailDialog(record: displayRecord),
    );
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    _loadRecords();
  }

  void _onPageSizeChanged(int pageSize) {
    setState(() {
      _pageSize = pageSize;
      _currentPage = 0;
    });
    _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return AttractionLayout(
      title: 'Visit Records',
      selectedIndex: 2,
      onNavSelected: (i) {},
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        floatingActionButton: isMobile
            ? FloatingActionButton.extended(
                onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.attractionVisitEntry),
                label: const Text('Create Record'),
                backgroundColor: AppColors.primaryCyan,
                foregroundColor: AppColors.textWhite,
                icon: const Icon(Icons.add_rounded),
              )
            : null,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToolbar(isMobile),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryCyan))
                  : _buildTable(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: const Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMobile) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Visit Records', style: TextStyle(color: AppColors.textWhite, fontSize: 17, fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    if (_dateFrom != null || _dateTo != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextButton.icon(
                          onPressed: _clearDateRange,
                          icon: const Icon(Icons.clear_rounded, size: 16, color: AppColors.textGray),
                          label: Text('Clear Dates', style: TextStyle(color: AppColors.textGray, fontSize: 12)),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: () => _pickDateRange(context),
                      icon: const Icon(Icons.calendar_today_rounded, size: 16),
                      label: const Text('Date Range'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.inputBackground, foregroundColor: AppColors.textWhite, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7))),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.attractionVisitEntry),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Create Record'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primaryCyan, foregroundColor: AppColors.textWhite, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7))),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 34,
                    decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.inputBorder)),
                    child: Row(children: [
                      const SizedBox(width: 8),
                      const Icon(Icons.search_rounded, size: 16, color: AppColors.textGray),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: 'Search records...', hintStyle: TextStyle(color: AppColors.textSubtle, fontSize: 12.5)),
                          style: TextStyle(color: AppColors.textWhite, fontSize: 12.5),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    value: _originFilter,
                    decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: AppColors.inputBackground),
                    dropdownColor: AppColors.cardBackground,
                    style: const TextStyle(color: AppColors.textWhite, fontSize: 12.5),
                    items: _originOptions.map((v) {
                      final label = v == 'all' ? 'All Nationalities' : (v == 'domestic' ? 'Domestic' : 'International');
                      return DropdownMenuItem(value: v, child: Text(label));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _originFilter = val;
                          _currentPage = 0;
                        });
                        _loadRecords();
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
          if (isMobile) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Visit Records', style: TextStyle(color: AppColors.textWhite, fontSize: 17, fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    IconButton(icon: const Icon(Icons.filter_alt_rounded, color: AppColors.textGray, size: 20), onPressed: () => _pickDateRange(context)),
                    IconButton(icon: const Icon(Icons.add_rounded, color: AppColors.primaryCyan, size: 22), onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.attractionVisitEntry)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 34,
              decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.inputBorder)),
              child: Row(children: [
                const SizedBox(width: 8),
                const Icon(Icons.search_rounded, size: 16, color: AppColors.textGray),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: 'Search...', hintStyle: TextStyle(color: AppColors.textSubtle, fontSize: 12.5)),
                    style: TextStyle(color: AppColors.textWhite, fontSize: 12.5),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTable() {
    final displayed = _filteredRecords;

    if (_loadError != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: AppColors.accentRed, size: 32),
          const SizedBox(height: 8),
          Text(_loadError!, style: TextStyle(color: AppColors.textGray, fontSize: 13)),
          const SizedBox(height: 12),
          TextButton(onPressed: _loadRecords, child: Text('Retry', style: TextStyle(color: AppColors.primaryCyan))),
        ]),
      );
    }

    if (displayed.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.document_scanner_outlined, color: AppColors.textSubtle, size: 40),
          const SizedBox(height: 8),
          Text(_searchCtrl.text.isNotEmpty || _dateFrom != null || _originFilter != 'all'
              ? 'No matching records found.'
              : 'No visit records yet.', style: TextStyle(color: AppColors.textGray, fontSize: 13)),
        ]),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: DataTable(
                columnSpacing: 14,
                headingRowHeight: 36,
                dataRowHeight: 40,
                headingTextStyle: TextStyle(color: AppColors.textGray, fontSize: 11.5, fontWeight: FontWeight.w600),
                dataTextStyle: TextStyle(color: AppColors.textWhite, fontSize: 12.5),
                border: TableBorder.all(color: AppColors.cardBorder),
                columns: const [
                DataColumn(label: Text('Date', style: TextStyle(color: AppColors.textGray))),
                DataColumn(label: Text('Guests', style: TextStyle(color: AppColors.textGray)), numeric: true),
                DataColumn(label: Text('Nationality', style: TextStyle(color: AppColors.textGray))),
                DataColumn(label: Text('Location', style: TextStyle(color: AppColors.textGray))),
                DataColumn(label: Text('Created', style: TextStyle(color: AppColors.textGray))),
                DataColumn(label: Text('Actions', style: TextStyle(color: AppColors.textGray))),
              ],
              rows: displayed.map((r) => DataRow(
                cells: [
                  DataCell(Text(_fmtDate(r.visitDate))),
                  DataCell(Text(r.guestCount.toString())),
                  DataCell(Text(_nationalityLabel(r))),
                  DataCell(Text(_locationDisplay(r))),
                  DataCell(Text(r.createdAt != null ? _fmtDateTime(r.createdAt) : '-')),
                  DataCell(Row(children: [
                    Icon(Icons.visibility_rounded, size: 16, color: AppColors.primaryCyan),
                    const SizedBox(width: 4),
                    Text('View', style: TextStyle(color: AppColors.primaryCyan, fontSize: 11.5)),
                  ])),
                ],
                onSelectChanged: (_) => _showDetail(r),
              )).toList(),
            ),
          ),
        ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Paginator(
            currentPage: _currentPage,
            totalPages: _totalPages,
            totalItems: _totalItems,
            pageSize: _pageSize,
            pageSizeOptions: _pageSizeOptions,
            onPageSizeChanged: _onPageSizeChanged,
            onPageChanged: _onPageChanged,
          ),
        ),
      ],
    );
  }
}
