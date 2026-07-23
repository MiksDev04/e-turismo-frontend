// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app/core/services/admin_page_cache.dart';
import 'package:app/ui/shared/pages/error_page.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/core/services/connectivity_service.dart';
import 'package:app/core/services/file_saver.dart';
import 'package:app/ui/shared/layouts/admin_layout.dart';
import 'package:app/ui/shared/widgets/paginator.dart';
import 'package:app/api/admin_report_api.dart';
import 'package:app/ui/admin/widgets/report_view_modal.dart';

// ─── Admin Reports Page ───────────────────────────────────────────────────────

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  final ReportService _reportService = ReportService();

  List<ReportBatch> _batches = [];

  bool _loadingReports = false;
  int? _errorCode;
  String? _fetchError;
  String _filterYear = '';
  String _filterMonth = '';
  int _currentPage = 0;
  int _pageSize = 10;
  int _totalPages = 0;
  int _totalItems = 0;

  static const List<int> _pageSizeOptions = [10, 20, 30];

  static const List<String> _months = [
    'All Months',
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

  static const List<String> _years = [
    'All Years',
    '2026',
    '2025',
    '2024',
    '2023',
    '2022',
  ];

  @override
  void initState() {
    super.initState();
    final cache = AdminPageCacheService();
    if (cache.hasData(AdminPageCacheKeys.reports)) {
      final cached = cache.get<Map<String, dynamic>>(AdminPageCacheKeys.reports)!;
      _batches = cached['batches'] as List<ReportBatch>;
      _totalPages = cached['totalPages'] as int;
      _totalItems = cached['totalItems'] as int;
      _loadingReports = false;
    } else {
      _fetchBatches();
    }
  }

  Future<void> _fetchBatches() async {
    if (!mounted) return;
    setState(() {
      _loadingReports = true;
      _fetchError = null;
      _errorCode = null;
    });
    try {
      final result = await _reportService.fetchReportBatches(
        page: _currentPage + 1,
        pageSize: _pageSize,
        year: _filterYear.isNotEmpty ? _filterYear : null,
        month: _filterMonth.isNotEmpty ? _filterMonth : null,
      );

      if (!mounted) return;
      setState(() {
        _batches = result.data;
        _totalPages = result.pageCount;
        _totalItems = result.totalCount;
      });
      AdminPageCacheService().set(AdminPageCacheKeys.reports, {
        'batches': _batches,
        'totalPages': _totalPages,
        'totalItems': _totalItems,
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchError = e.message;
        _errorCode = e.statusCode;
      });
    } catch (e) {
      final code = await classifyError(e);
      if (!mounted) return;
      setState(() {
        _fetchError = e.toString();
        _errorCode = code;
      });
    } finally {
      if (mounted) setState(() => _loadingReports = false);
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (_) => _CreateBatchDialog(
        months: _months.where((m) => m != 'All Months').toList(),
        years: _years.where((y) => y != 'All Years').toList(),
        onCreate: ({
          required String reportType,
          required String variant,
          required int year,
          required List<int> months,
        }) {
          Navigator.pop(context);
          _onCreateBatch(reportType: reportType, variant: variant, year: year, months: months);
        },
      ),
    );
  }

  Future<void> _onCreateBatch({
    required String reportType,
    required String variant,
    required int year,
    required List<int> months,
  }) async {
    try {
      final result = await _reportService.createBatch(CreateBatchParams(
        reportType: reportType,
        reportVariant: variant,
        periodYear: year,
        periodMonths: months,
      ));
      await _fetchBatches();
      AdminPageCacheService().invalidate(AdminPageCacheKeys.dashboardDash);
      if (!mounted) return;
      if (result.alreadyExisted) {
        _showWarning('Report already exists');
      } else {
        _showSuccess('Report batch created successfully');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      _showError('Error creating report batch: $e');
    }
  }

  void _viewReport(ReportBatch batch) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => ReportViewerModal(
        batch: batch,
        onDownload: (format) => _downloadReport(batch, format: format),
      ),
    );
  }

  Future<void> _downloadReport(ReportBatch batch, {String format = 'xlsx'}) async {
    try {
      _showSuccess('Downloading $format...');
      final bytes = await _reportService.downloadReport(DownloadReportParams(
        reportType: batch.reportType,
        reportVariant: batch.reportVariant,
        periodYear: batch.periodYear,
        periodMonths: batch.periodMonths,
        format: format,
      ));

      final typePrefix = batch.reportType.toUpperCase();
      final periodSlug = batch.displayPeriod.replaceAll(', ', '_').replaceAll(' ', '');
      final fileName = '${typePrefix}_${batch.reportVariant}_${periodSlug}.$format';
      await _saveFile(fileName, bytes);
      if (!mounted) return;
      _showSuccess('File downloaded: $fileName');
    } catch (e) {
      if (mounted) _showError('Error downloading file: $e');
    }
  }

  Future<void> _saveFile(String fileName, List<int> bytes) async {
    // Use the file_saver service
    await saveFileToDownloads(fileName, bytes);
  }

  void _clearFilters() {
    setState(() {
      _filterYear = '';
      _filterMonth = '';
      _currentPage = 0;
    });
    _fetchBatches();
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF00C48C),
        duration: const Duration(seconds: 3),
        content: Text(msg, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFFF4D6A),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showWarning(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFFFCA28),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      title: 'Reports',
      selectedIndex: 2,
      onNavSelected: (_) {},
      child: _fetchError != null
          ? ErrorPage(statusCode: _errorCode ?? 500, onRetry: _fetchBatches)
          : LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 900;
                return RefreshIndicator(
                  onRefresh: _fetchBatches,
                  color: AppColors.primaryCyan,
                  backgroundColor: AppColors.cardBackground,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(isNarrow ? 16 : 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PageHeader(
                          isNarrow: isNarrow,
                          onGenerateTap: _showCreateDialog,
                        ),
                        const SizedBox(height: 16),
                        _FilterSection(
                          isNarrow: isNarrow,
                          months: _months,
                          years: _years,
                          selectedMonth: _filterMonth,
                          selectedYear: _filterYear,
                          onMonthChanged: (v) {
                            setState(() {
                              _filterMonth = v ?? '';
                              _currentPage = 0;
                            });
                            _fetchBatches();
                          },
                          onYearChanged: (v) {
                            setState(() {
                              _filterYear = v ?? '';
                              _currentPage = 0;
                            });
                            _fetchBatches();
                          },
                          onClear: _clearFilters,
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel(
                          icon: Icons.table_chart_rounded,
                          label: 'Report Batches',
                          subtitle: 'Live data \u2014 no files stored',
                        ),
                        const SizedBox(height: 12),
                        if (_loadingReports)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: CircularProgressIndicator(
                                color: AppColors.primaryCyan,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        else
                          _ReportBatchesTable(
                            rows: _batches,
                            isLoading: false,
                            onView: _viewReport,
                          ),
                        if (!_loadingReports) ...[
                          const SizedBox(height: 12),
                          Paginator(
                            currentPage: _currentPage,
                            totalPages: _totalPages,
                            totalItems: _totalItems,
                            pageSize: _pageSize,
                            pageSizeOptions: _pageSizeOptions,
                            onPageSizeChanged: (size) {
                              setState(() {
                                _pageSize = size;
                                _currentPage = 0;
                              });
                              _fetchBatches();
                            },
                            onPageChanged: (page) {
                              setState(() => _currentPage = page);
                              _fetchBatches();
                            },
                          ),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ─── Section Label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final IconData icon;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryCyan.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primaryCyan, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.textGray, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Report Batches Table ────────────────────────────────────────────────────

class _ReportBatchesTable extends StatelessWidget {
  const _ReportBatchesTable({
    required this.rows,
    required this.isLoading,
    required this.onView,
  });

  final List<ReportBatch> rows;
  final bool isLoading;
  final void Function(ReportBatch) onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (_, constraints) =>
                _TableHeader(isNarrow: constraints.maxWidth < 700),
          ),
          const Divider(color: AppColors.cardBorder, height: 1),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryCyan,
              ),
            )
          else if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Text(
                'No report batches yet. Use "Create Report" to start one.',
                style: TextStyle(color: AppColors.textGray, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.cardBorder, height: 1),
              itemBuilder: (_, i) => LayoutBuilder(
                builder: (_, constraints) => _TableRow(
                  batch: rows[i],
                  isNarrow: constraints.maxWidth < 700,
                  onView: () => onView(rows[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.isNarrow});
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    if (isNarrow) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: _HeaderCell('Report')),
            SizedBox(width: 72, child: _HeaderCell('Actions')),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 1, child: _HeaderCell('Type')),
          Expanded(flex: 2, child: _HeaderCell('Variant')),
          Expanded(flex: 2, child: _HeaderCell('Period')),
          Expanded(flex: 2, child: _HeaderCell('Created')),
          Expanded(flex: 2, child: _HeaderCell('Last Viewed')),
          SizedBox(width: 88, child: _HeaderCell('Actions')),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.batch,
    required this.isNarrow,
    required this.onView,
  });

  final ReportBatch batch;
  final bool isNarrow;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final createdStr =
        '${batch.createdAt.year}-'
        '${batch.createdAt.month.toString().padLeft(2, '0')}-'
        '${batch.createdAt.day.toString().padLeft(2, '0')}';

    final viewedStr = batch.lastViewedAt != null
        ? '${batch.lastViewedAt!.year}-'
          '${batch.lastViewedAt!.month.toString().padLeft(2, '0')}-'
          '${batch.lastViewedAt!.day.toString().padLeft(2, '0')}'
        : 'Never';

    if (isNarrow) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TypeBadge(type: batch.reportType),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    batch.variantLabel,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Period',
                        style: TextStyle(
                          color: AppColors.textSubtle,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        batch.displayPeriod,
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Created',
                        style: TextStyle(
                          color: AppColors.textSubtle,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        createdStr,
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last Viewed',
                        style: TextStyle(
                          color: AppColors.textSubtle,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        viewedStr,
                        style: TextStyle(
                          color: viewedStr == 'Never'
                              ? AppColors.textSubtle
                              : AppColors.textGray,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: _ViewButton(onTap: onView),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: _TypeBadge(type: batch.reportType),
          ),
          Expanded(
            flex: 2,
            child: Text(
              batch.variantLabel,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              batch.displayPeriod,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              createdStr,
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              viewedStr,
              style: TextStyle(
                color: viewedStr == 'Never' ? AppColors.textSubtle : AppColors.textGray,
                fontSize: 13,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: _ViewButton(onTap: onView),
          ),
        ],
      ),
    );
  }
}

// ─── View Button ──────────────────────────────────────────────────────────────

class _ViewButton extends StatefulWidget {
  const _ViewButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ViewButton> createState() => _ViewButtonState();
}

class _ViewButtonState extends State<_ViewButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.primaryCyan;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: Tooltip(
            message: 'View Report',
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _hovered
                      ? color.withOpacity(0.12)
                      : color.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _hovered
                        ? color.withOpacity(0.7)
                        : color.withOpacity(0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.open_in_full_rounded,
                      color: _hovered ? color : color.withOpacity(0.7),
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'View',
                      style: TextStyle(
                        color: _hovered ? color : color.withOpacity(0.7),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Type Badge ──────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final label = type.toUpperCase();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primaryCyan.withOpacity(0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.primaryCyan.withOpacity(0.2)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.primaryCyan,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Small shared widgets ─────────────────────────────────────────────────────

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textGray,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ─── Create Report Dialog ────────────────────────────────────────────────────

class _CreateBatchDialog extends StatefulWidget {
  const _CreateBatchDialog({
    required this.months,
    required this.years,
    required this.onCreate,
  });

  final List<String> months;
  final List<String> years;
  final void Function({
    required String reportType,
    required String variant,
    required int year,
    required List<int> months,
  }) onCreate;

  @override
  State<_CreateBatchDialog> createState() => _CreateBatchDialogState();
}

class _CreateBatchDialogState extends State<_CreateBatchDialog> {
  String _reportType = 'dae';
  String _variant = 'daily';
  String? _selectedYear;
  String? _selectedMonth;
  int? _rangeStart;
  int? _rangeEnd;

  bool get _isDae => _reportType == 'dae';
  bool get _isVar => _reportType == 'var';
  bool get _needsSingleMonth => _isDae && (_variant == 'daily' || _variant == 'summary');
  bool get _needsMultiMonth => (_isDae && _variant == 'series') || _isVar;

  bool get _canCreate {
    if (_selectedYear == null) return false;
    if (_needsSingleMonth) return _selectedMonth != null;
    if (_needsMultiMonth) return _rangeStart != null && _rangeEnd != null;
    return false;
  }

  List<int> get _selectedRange {
    if (_rangeStart == null || _rangeEnd == null) return [];
    final s = _rangeStart!;
    final e = _rangeEnd!;
    final lo = s <= e ? s : e;
    final hi = s <= e ? e : s;
    return List.generate(hi - lo + 1, (i) => lo + i);
  }

  static int _monthIndex(String name) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return names.indexOf(name) + 1;
  }

  void _onRangeTap(int month) {
    setState(() {
      if (_rangeStart == null || _rangeEnd != null) {
        _rangeStart = month;
        _rangeEnd = null;
      } else {
        _rangeEnd = month;
      }
    });
  }

  void _resetRange() {
    setState(() {
      _rangeStart = null;
      _rangeEnd = null;
    });
  }

  String get _dialogTitle {
    if (_isVar) return 'Create VAR Report';
    return 'Create DAE Report';
  }

  String get _dialogSubtitle {
    if (_isVar) return 'Select the period for the VAR report';
    return 'View live data \u2014 no file generated until you download';
  }

  String get _effectiveVariant => _isVar ? 'total' : _variant;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DialogHeader(
                title: _dialogTitle,
                subtitle: _dialogSubtitle,
                onClose: () => Navigator.pop(context),
              ),
              const SizedBox(height: 24),
              const _DialogLabel('Report Type'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _TypeCard(
                      icon: Icons.description_rounded,
                      label: 'DAE',
                      subtitle: 'DAE-1B Form',
                      selected: _isDae,
                      onTap: () => setState(() {
                        _reportType = 'dae';
                        _rangeStart = null;
                        _rangeEnd = null;
                        _selectedMonth = null;
                        _variant = 'daily';
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TypeCard(
                      icon: Icons.summarize_rounded,
                      label: 'VAR',
                      subtitle: 'VAR Report',
                      selected: _isVar,
                      onTap: () => setState(() {
                        _reportType = 'var';
                        _rangeStart = null;
                        _rangeEnd = null;
                        _selectedMonth = null;
                      }),
                    ),
                  ),
                ],
              ),
              if (_isDae) ...[
                const SizedBox(height: 14),
                const _DialogLabel('Report Variant'),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.backgroundDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      _VariantOption(
                        label: 'Daily Breakdown',
                        subtitle: 'Sheet 1 \u2014 Per-day columns for one month',
                        selected: _variant == 'daily',
                        onTap: () => setState(() {
                          _variant = 'daily';
                          _rangeStart = null;
                          _rangeEnd = null;
                          _selectedMonth = null;
                        }),
                        isFirst: true,
                      ),
                      const Divider(color: AppColors.cardBorder, height: 1),
                      _VariantOption(
                        label: 'Country Summary',
                        subtitle: 'Sheet 2 \u2014 Monthly totals by country',
                        selected: _variant == 'summary',
                        onTap: () => setState(() {
                          _variant = 'summary';
                          _rangeStart = null;
                          _rangeEnd = null;
                          _selectedMonth = null;
                        }),
                      ),
                      const Divider(color: AppColors.cardBorder, height: 1),
                      _VariantOption(
                        label: 'Monthly Series',
                        subtitle: 'Sheet 3 \u2014 Month-by-month totals',
                        selected: _variant == 'series',
                        onTap: () => setState(() {
                          _variant = 'series';
                          _selectedMonth = null;
                        }),
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const _DialogLabel('Year'),
              const SizedBox(height: 6),
              _DropdownField<String>(
                hint: 'Select year',
                value: _selectedYear,
                items: widget.years,
                itemLabel: (y) => y,
                onChanged: (v) => setState(() => _selectedYear = v),
              ),
              const SizedBox(height: 14),
              if (_needsSingleMonth) ...[
                const _DialogLabel('Month'),
                const SizedBox(height: 6),
                _DropdownField<String>(
                  hint: 'Select month',
                  value: _selectedMonth,
                  items: widget.months,
                  itemLabel: (m) => m,
                  onChanged: (v) => setState(() => _selectedMonth = v),
                ),
              ] else if (_needsMultiMonth) ...[
                const _DialogLabel('Month Range'),
                const SizedBox(height: 6),
                _MonthRangeGrid(
                  months: widget.months,
                  rangeStart: _rangeStart,
                  rangeEnd: _rangeEnd,
                  onMonthTap: _onRangeTap,
                  onReset: _resetRange,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textGray, fontSize: 13),
                    ),
                  ),
                  _CreateButton(
                    enabled: _canCreate,
                    onPressed: () {
                      final months = _needsSingleMonth
                          ? [_monthIndex(_selectedMonth!)]
                          : _selectedRange;
                      widget.onCreate(
                        reportType: _reportType,
                        variant: _effectiveVariant,
                        year: int.parse(_selectedYear!),
                        months: months,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dialog Header ─────────────────────────────────────────────────────────

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryCyan.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.description_rounded,
            color: AppColors.primaryCyan,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 11.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onClose,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.backgroundDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Icon(
              Icons.close_rounded,
              color: AppColors.textGray,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Report Type Card ──────────────────────────────────────────────────────

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryCyan.withOpacity(0.1)
              : AppColors.backgroundDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primaryCyan.withOpacity(0.6)
                : AppColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? AppColors.primaryCyan : AppColors.textGray,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? AppColors.primaryCyan : AppColors.textWhite,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: selected ? AppColors.textGray : AppColors.textSubtle,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle_rounded,
                color: AppColors.primaryCyan,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Create Button ─────────────────────────────────────────────────────────

class _CreateButton extends StatelessWidget {
  const _CreateButton({
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: enabled
              ? AppColors.primaryCyan
              : AppColors.primaryCyan.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_rounded,
              size: 15,
              color: enabled ? Colors.black : Colors.black45,
            ),
            const SizedBox(width: 5),
            Text(
              'Generate',
              style: TextStyle(
                color: enabled ? Colors.black : Colors.black45,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantOption extends StatelessWidget {
  const _VariantOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(10) : Radius.zero,
        bottom: isLast ? const Radius.circular(10) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Radio<String>(
                value: label,
                groupValue: selected ? label : null,
                onChanged: (_) => onTap(),
                activeColor: AppColors.primaryCyan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? AppColors.textWhite : AppColors.textGray,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: selected ? AppColors.textGray : AppColors.textSubtle,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Month Range Grid ─────────────────────────────────────────────────────

class _MonthRangeGrid extends StatelessWidget {
  const _MonthRangeGrid({
    required this.months,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onMonthTap,
    required this.onReset,
  });

  final List<String> months;
  final int? rangeStart;
  final int? rangeEnd;
  final void Function(int) onMonthTap;
  final VoidCallback onReset;

  bool _inRange(int month) {
    if (rangeStart == null) return false;
    if (rangeEnd != null) {
      final lo = rangeStart! <= rangeEnd! ? rangeStart! : rangeEnd!;
      final hi = rangeStart! <= rangeEnd! ? rangeEnd! : rangeStart!;
      return month >= lo && month <= hi;
    }
    return month == rangeStart;
  }

  bool _isStart(int month) => rangeStart == month;
  bool _isEnd(int month) => rangeEnd != null && rangeEnd == month;

  String get _rangeLabel {
    if (rangeStart == null) return 'Tap a month to start';
    if (rangeEnd == null) return '${months[rangeStart! - 1]} \u2014 tap end month';
    final lo = rangeStart! <= rangeEnd! ? rangeStart! : rangeEnd!;
    final hi = rangeStart! <= rangeEnd! ? rangeEnd! : rangeStart!;
    if (lo == hi) return months[lo - 1];
    return '${months[lo - 1]} \u2013 ${months[hi - 1]}  (${hi - lo + 1} months)';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(months.length, (i) {
              final monthNum = i + 1;
              final inRange = _inRange(monthNum);
              final isStart = _isStart(monthNum);
              final isEnd = _isEnd(monthNum);
              final isEdge = isStart || isEnd;

              return GestureDetector(
                onTap: () => onMonthTap(monthNum),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: inRange
                        ? AppColors.primaryCyan.withOpacity(isEdge ? 0.25 : 0.12)
                        : AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: inRange
                          ? AppColors.primaryCyan.withOpacity(isEdge ? 0.8 : 0.4)
                          : AppColors.cardBorder,
                    ),
                  ),
                  child: Text(
                    months[i].substring(0, 3),
                    style: TextStyle(
                      color: inRange ? AppColors.primaryCyan : AppColors.textGray,
                      fontSize: 12,
                      fontWeight: isEdge ? FontWeight.w700 : (inRange ? FontWeight.w600 : FontWeight.w400),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                rangeEnd != null ? Icons.check_circle_rounded : Icons.touch_app_rounded,
                color: rangeEnd != null ? AppColors.primaryCyan : AppColors.textSubtle,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _rangeLabel,
                  style: TextStyle(
                    color: rangeEnd != null ? AppColors.primaryCyan : AppColors.textSubtle,
                    fontSize: 12,
                    fontWeight: rangeEnd != null ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (rangeStart != null)
                GestureDetector(
                  onTap: onReset,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Text(
                      'Clear',
                      style: TextStyle(color: AppColors.textGray, fontSize: 10),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Shared small helpers ─────────────────────────────────────────────────────

class _DialogLabel extends StatelessWidget {
  const _DialogLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textGray,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.hint,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final String hint;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final void Function(T?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          hint: Text(
            hint,
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 13),
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textGray,
            size: 20,
          ),
          style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
          dropdownColor: AppColors.cardBackground,
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    itemLabel(item),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── Filter Section ───────────────────────────────────────────────────────────

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.isNarrow,
    required this.months,
    required this.years,
    required this.selectedMonth,
    required this.selectedYear,
    required this.onMonthChanged,
    required this.onYearChanged,
    required this.onClear,
  });

  final bool isNarrow;
  final List<String> months;
  final List<String> years;
  final String selectedMonth;
  final String selectedYear;
  final void Function(String?) onMonthChanged;
  final void Function(String?) onYearChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final monthValue = selectedMonth.isEmpty ? 'All Months' : selectedMonth;
    final yearValue = selectedYear.isEmpty ? 'All Years' : selectedYear;

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _FilterDropdown(
                  value: monthValue,
                  items: months,
                  onChanged: onMonthChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterDropdown(
                  value: yearValue,
                  items: years,
                  onChanged: onYearChanged,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _FilterDropdown(
            value: monthValue,
            items: months,
            onChanged: onMonthChanged,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FilterDropdown(
            value: yearValue,
            items: years,
            onChanged: onYearChanged,
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onClear,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.clear_rounded, color: AppColors.textGray, size: 14),
                SizedBox(width: 4),
                Text(
                  'Clear',
                  style: TextStyle(color: AppColors.textGray, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          iconEnabledColor: AppColors.textGray,
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
          dropdownColor: AppColors.cardBackground,
          items: items
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(
                      item,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────
class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.isNarrow,
    required this.onGenerateTap,
  });

  final bool isNarrow;
  final VoidCallback onGenerateTap;

  @override
  Widget build(BuildContext context) {
    final generateBtn = _HeaderButton(
      icon: Icons.add_rounded,
      label: isNarrow ? 'Generate' : 'Generate Report',
      isPrimary: true,
      onTap: onGenerateTap,
    );

    const titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reports',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'View live data or download as Excel/PDF',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: titleBlock),
        generateBtn,
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.isPrimary = false,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final Color fg;

    if (isPrimary) {
      bg = AppColors.primaryCyan;
      border = AppColors.primaryCyan;
      fg = Colors.white;
    } else {
      bg = AppColors.cardBackground;
      border = AppColors.cardBorder;
      fg = AppColors.textGray;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: isPrimary
            ? BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                ),
                borderRadius: BorderRadius.circular(8),
              )
            : BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: isPrimary ? 14 : 16),
            if (label != null) ...[
              SizedBox(width: isPrimary ? 4 : 6),
              Text(
                label!,
                style: TextStyle(
                  color: fg,
                  fontSize: isPrimary ? 12 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
