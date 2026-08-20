import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/api/attraction_visit_record_api.dart';
import '../../shared/layouts/attraction_layout.dart';
import '../../shared/widgets/paginator.dart';
import '../../shared/widgets/action_icon_button.dart';
import '../../../router/app_routes.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmtDate(DateTime dt) {
  return "${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
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

// ─── Visit Records Page ───────────────────────────────────────────────────────

class AttractionVisitRecordsPage extends StatefulWidget {
  const AttractionVisitRecordsPage({super.key});

  @override
  State<AttractionVisitRecordsPage> createState() =>
      _AttractionVisitRecordsPageState();
}

class _AttractionVisitRecordsPageState extends State<AttractionVisitRecordsPage> {
  final _api = AttractionVisitRecordApi();

  List<VisitRecord> _records = [];
  bool _isLoading = true;
  String? _loadError;

  bool _showFilters = false;
  int _currentPage = 0;
  int _pageSize = 10;
  int _totalPages = 0;
  int _totalItems = 0;

  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const List<int> _pageSizeOptions = [10, 20, 30];

  @override
  void initState() {
    super.initState();
    _loadRecords();
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
      );

      if (!mounted) return;
      if (result.isSuccess) {
        final data = result.data!;
        setState(() {
          _records = data.data;
          _totalPages = data.pageCount;
          _totalItems = data.totalCount;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _loadError = result.error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Failed to load records: $e';
      });
    }
  }

  // ── Date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickDate(BuildContext context, bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.dark(
            primary: AppColors.primaryCyan,
            onPrimary: Colors.black,
            primaryContainer: AppColors.primaryCyan.withOpacity(0.25),
            onPrimaryContainer: AppColors.primaryCyan,
            surface: AppColors.cardBackground,
            onSurface: AppColors.textWhite,
            onSurfaceVariant: AppColors.textGray,
            outline: AppColors.cardBorder,
            surfaceVariant: AppColors.inputBackground,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: AppColors.cardBackground,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.cardBorder),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryCyan),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
      _currentPage = 0;
    });
    _loadRecords();
  }

  void _clearAllFilters() {
    setState(() {
      _dateFrom = null;
      _dateTo = null;
      _currentPage = 0;
    });
    _loadRecords();
  }

  void _reload() {
    _currentPage = 0;
    _loadRecords();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AttractionLayout(
      title: 'Visit Records',
      selectedIndex: 2,
      onNavSelected: (_) {},
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isNarrow ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PageHeader(
                        showFilters: _showFilters,
                        onFilterToggle: () =>
                            setState(() => _showFilters = !_showFilters),
                        onCreate: () => Navigator.pushReplacementNamed(
                            context, AppRoutes.attractionVisitEntry),
                        isNarrow: isNarrow,
                        totalRecords: _totalItems,
                      ),
                      const SizedBox(height: 8),
                      if (_showFilters) ...[
                        _FiltersSection(
                          dateFrom: _dateFrom,
                          dateTo: _dateTo,
                          onDateFromTap: () => _pickDate(context, true),
                          onDateToTap: () => _pickDate(context, false),
                          onClearAll: _clearAllFilters,
                          isNarrow: isNarrow,
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryCyan,
                            ),
                          ),
                        )
                      else if (_loadError != null)
                        _ErrorBanner(
                          message: _loadError!,
                          onRetry: _loadRecords,
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _VisitTable(
                              records: _records,
                              isNarrow: isNarrow,
                            ),
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
                                _loadRecords();
                              },
                              onPageChanged: (page) {
                                setState(() => _currentPage = page);
                                _loadRecords();
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Error Banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentRed.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.accentRed,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.accentRed,
                fontSize: 13.5,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text(
              'Retry',
              style: TextStyle(color: AppColors.primaryCyan),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Filters Section ──────────────────────────────────────────────────────────

class _FiltersSection extends StatelessWidget {
  const _FiltersSection({
    required this.dateFrom,
    required this.dateTo,
    required this.onDateFromTap,
    required this.onDateToTap,
    required this.onClearAll,
    required this.isNarrow,
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final VoidCallback onDateFromTap;
  final VoidCallback onDateToTap;
  final VoidCallback onClearAll;
  final bool isNarrow;

  bool get _hasActiveFilters => dateFrom != null || dateTo != null;

  @override
  Widget build(BuildContext context) {
    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _DateFilter(
                  label: 'Date From',
                  date: dateFrom,
                  onTap: onDateFromTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DateFilter(
                  label: 'Date To',
                  date: dateTo,
                  onTap: onDateToTap,
                ),
              ),
            ],
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(height: 10),
            _ClearAllBtn(onTap: onClearAll),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _DateFilter(
            label: 'Date From',
            date: dateFrom,
            onTap: onDateFromTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DateFilter(
            label: 'Date To',
            date: dateTo,
            onTap: onDateToTap,
          ),
        ),
        const SizedBox(width: 12),
        if (_hasActiveFilters) ...[
          const SizedBox(width: 12),
          _ClearAllBtn(onTap: onClearAll),
        ],
      ],
    );
  }
}

// ─── Filter Widgets ───────────────────────────────────────────────────────────

class _DateFilter extends StatelessWidget {
  const _DateFilter({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  String get _display {
    if (date == null) return 'mm/dd/yyyy';
    return '${date!.month.toString().padLeft(2, '0')}/'
        '${date!.day.toString().padLeft(2, '0')}/${date!.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  color: AppColors.textSubtle,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _display,
                    style: TextStyle(
                      color: date != null
                          ? AppColors.textWhite
                          : AppColors.textSubtle,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ClearAllBtn extends StatelessWidget {
  const _ClearAllBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.clear_all, color: AppColors.textGray, size: 15),
            SizedBox(width: 5),
            Text(
              'Clear All',
              style: TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page Header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.showFilters,
    required this.onFilterToggle,
    required this.onCreate,
    required this.isNarrow,
    required this.totalRecords,
  });

  final bool showFilters;
  final VoidCallback onFilterToggle;
  final VoidCallback onCreate;
  final bool isNarrow;
  final int totalRecords;

  @override
  Widget build(BuildContext context) {
    final createBtn = FilledButton.icon(
      onPressed: onCreate,
      icon: const Icon(Icons.add_rounded, size: 16),
      label: const Text('Create Record'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryCyan,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    final filterBtn = _FilterPanelButton(
      isActive: showFilters,
      onTap: onFilterToggle,
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleSubtitle(totalRecords: totalRecords),
          const SizedBox(height: 12),
          Row(children: [createBtn, const SizedBox(width: 10), filterBtn]),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _TitleSubtitle(totalRecords: totalRecords),
        const Spacer(),
        createBtn,
        const SizedBox(width: 10),
        filterBtn,
      ],
    );
  }
}

class _TitleSubtitle extends StatelessWidget {
  const _TitleSubtitle({required this.totalRecords});
  final int totalRecords;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Visit Records ($totalRecords)',
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'View and manage all visitor entries',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

class _FilterPanelButton extends StatelessWidget {
  const _FilterPanelButton({required this.isActive, required this.onTap});
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryCyan.withOpacity(0.15)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.primaryCyan : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_rounded,
              color: isActive ? AppColors.primaryCyan : AppColors.textGray,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'Filters',
              style: TextStyle(
                color: isActive ? AppColors.primaryCyan : AppColors.textGray,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Visit Table ──────────────────────────────────────────────────────────────

class _VisitTable extends StatelessWidget {
  const _VisitTable({
    required this.records,
    required this.isNarrow,
  });

  final List<VisitRecord> records;
  final bool isNarrow;

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
          if (!isNarrow) ...[
            const _TableHeader(),
            const Divider(color: AppColors.cardBorder, height: 1),
          ],
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No records found.',
                  style: TextStyle(color: AppColors.textGray),
                ),
              ),
            )
          else
            ...records.map((r) {
              final isLast = r == records.last;
              return Column(
                children: [
                  if (isNarrow)
                    _RecordCard(record: r)
                  else
                    _RecordRow(record: r),
                  if (!isLast)
                    const Divider(color: AppColors.cardBorder, height: 1),
                ],
              );
            }),
        ],
      ),
    );
  }
}

// ─── Table Header ─────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: _HeaderCell('Date')),
          Expanded(flex: 1, child: _HeaderCell('Visitors')),
          Expanded(flex: 3, child: _HeaderCell('From')),
          Expanded(flex: 2, child: _HeaderCell('Actions')),
        ],
      ),
    );
  }
}

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

// ─── Table Row (wide) ─────────────────────────────────────────────────────────

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final VisitRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              _fmtDate(r.visitDate),
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '${r.guestCount}',
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _locationDisplay(r),
              style: const TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: _ActionButtons(
              onView: () => _showRecordModal(context, r),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Record Card (narrow) ─────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final VisitRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fmtDate(r.visitDate),
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _GuestBadge(count: r.guestCount),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _InfoChip(label: 'From', value: _locationDisplay(r)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ActionIconButton(
                icon: Icons.visibility_outlined,
                label: 'View',
                color: AppColors.accentGreen,
                showBorder: true,
                compact: true,
                onTap: () => _showRecordModal(context, r),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuestBadge extends StatelessWidget {
  const _GuestBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryCyan.withOpacity(0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.primaryCyan.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.people_outline,
            color: AppColors.primaryCyan,
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.primaryCyan,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(color: AppColors.textSubtle),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: AppColors.textGray),
          ),
        ],
      ),
    );
  }
}

// ─── Action Buttons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.onView});

  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        ActionIconButton(
          icon: Icons.visibility_outlined,
          label: 'View',
          color: AppColors.accentGreen,
          showBorder: true,
          compact: true,
          onTap: onView,
        ),
      ],
    );
  }
}

// ─── Full Record Modal ────────────────────────────────────────────────────────

void _showRecordModal(BuildContext context, VisitRecord record) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => _RecordDetailModal(record: record),
  );
}

class _RecordDetailModal extends StatelessWidget {
  const _RecordDetailModal({required this.record});
  final VisitRecord record;

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 560;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 16 : 40,
        vertical: 32,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.event_note_rounded,
                      color: AppColors.primaryCyan,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Visit Record Details',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textGray,
                      size: 20,
                    ),
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // ── Body ───────────────────────────────────────────────────
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.inputBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder.withOpacity(0.4)),
                      ),
                      child: const _ModalSectionLabel('Visit Information'),
                    ),
                    const SizedBox(height: 10),
                    _VisitInfoGrid(record: record),
                    const SizedBox(height: 24),

                    Container(
                      width: double.infinity,
                      height: 1,
                      color: AppColors.cardBorder.withOpacity(0.6),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.inputBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder.withOpacity(0.4)),
                      ),
                      child: const _ModalSectionLabel('Visitors Demographics'),
                    ),
                    const SizedBox(height: 12),

                    _GuestDemoGrid(record: record),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Visit Info Grid ──────────────────────────────────────────────────────────

class _VisitInfoGrid extends StatelessWidget {
  const _VisitInfoGrid({required this.record});
  final VisitRecord record;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.calendar_today,        'Visit Date',    _fmtDate(record.visitDate)),
      (Icons.people_outline,        'Total Visitors',  '${record.guestCount}'),
      (Icons.male_outlined,         'Male Visitors',   record.maleCount?.toString() ?? '-'),
      (Icons.female_outlined,       'Female Visitors', record.femaleCount?.toString() ?? '-'),
    ];

    const spacing = 12.0;
    const rowGap = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: rowGap,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _DetailField(
                  icon: item.$1,
                  label: item.$2,
                  value: item.$3,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── Guest Demographics Grid ──────────────────────────────────────────────────

class _GuestDemoGrid extends StatelessWidget {
  const _GuestDemoGrid({required this.record});
  final VisitRecord record;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.public_outlined,           'Country',         record.isForeign
          ? (record.country ?? '-')
          : 'Philippines'),
      (Icons.map_outlined,              'Province',        record.isForeign
          ? '-'
          : (record.province ?? '-')),
      (Icons.location_city_outlined,    'City/Municipality', record.isForeign
          ? '-'
          : (record.cityMunicipality ?? '-')),
    ];

    const spacing = 12.0;
    const rowGap = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: rowGap,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _DetailField(
                  icon: item.$1,
                  label: item.$2,
                  value: item.$3,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.textSubtle, size: 13),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSubtle,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Modal Helpers ────────────────────────────────────────────────────────────

class _ModalSectionLabel extends StatelessWidget {
  const _ModalSectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textWhite,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}
