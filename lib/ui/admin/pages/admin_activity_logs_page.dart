// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app/api/admin_activity_log_api.dart';
import 'package:app/api/base_api.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/core/services/connectivity_service.dart';
import 'package:app/ui/shared/pages/error_page.dart';
import 'package:app/ui/admin/models/activity_log_model.dart';
import 'package:app/ui/shared/layouts/admin_layout.dart';
import 'package:app/ui/shared/widgets/paginator.dart';

class AdminActivityLogsPage extends StatefulWidget {
  const AdminActivityLogsPage({super.key});

  @override
  State<AdminActivityLogsPage> createState() => _AdminActivityLogsPageState();
}

class _AdminActivityLogsPageState extends State<AdminActivityLogsPage> {
  final _api = AdminActivityLogApi();
  final _dateFormat = DateFormat('MMM dd, yyyy h:mm a');

  List<ActivityLog> _items = [];
  bool _loading = true;
  String? _error;
  int? _errorCode;

  int _page = 1;
  int _limit = 20;
  int _total = 0;

  String? _selectedActionType;
  DateTime? _startDate;
  DateTime? _endDate;

  static const _actionTypes = [
    'login_success',
    'login_failed',
    'password_changed',
    'email_changed',
    'password_reset_requested',
    'password_reset_completed',
    'business_status_changed',
    'attraction_status_changed',
    'guest_record_created',
    'guest_record_updated',
    'guest_record_checked_out',
    'visit_log_created',
    'profile_updated',
    'report_generated',
  ];

  static const _friendlyLabels = {
    'login_success': 'Login',
    'login_failed': 'Failed login',
    'password_changed': 'Password changed',
    'email_changed': 'Email changed',
    'password_reset_requested': 'Password reset requested',
    'password_reset_completed': 'Password reset completed',
    'business_status_changed': 'Business registration reviewed',
    'attraction_status_changed': 'Attraction registration reviewed',
    'guest_record_created': 'Guest record created (accommodation)',
    'guest_record_updated': 'Guest record updated (accommodation)',
    'guest_record_checked_out': 'Guest checked out (accommodation)',
    'visit_log_created': 'Visit log created (attraction)',
    'profile_updated': 'Account info updated',
    'report_generated': 'Report generated',
  };

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorCode = null;
    });
    try {
      final res = await _api.fetchActivityLogs(
        page: _page,
        limit: _limit,
        actionType: _selectedActionType,
        dateFrom: _startDate != null
            ? DateFormat('yyyy-MM-dd').format(_startDate!)
            : null,
        dateTo: _endDate != null
            ? DateFormat('yyyy-MM-dd').format(_endDate!)
            : null,
      );
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _total = res.total;
        _page = res.page;
        _limit = res.limit;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _errorCode = e.statusCode;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final code = await classifyError(e);
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _errorCode = code;
        _loading = false;
      });
    }
  }

  String _buildSentence(ActivityLog log) {
    final type = log.actionType;
    final target = log.targetName;
    final details = log.details ?? '';
    switch (type) {
      case 'login_success':
        return 'Logged in';
      case 'login_failed':
        return 'Failed login';
      case 'password_changed':
        return 'Changed their password';
      case 'email_changed':
        return details.isEmpty
            ? 'Changed their email'
            : 'Changed their email: $details';
      case 'password_reset_requested':
        return 'Requested a password reset';
      case 'password_reset_completed':
        return 'Reset their password';
      case 'business_status_changed':
        if (target != null && target.isNotEmpty) {
          return details.isEmpty
              ? 'Reviewed business registration: $target'
              : 'Reviewed business registration: $target ($details)';
        }
        return details.isEmpty
            ? 'Reviewed business registration'
            : 'Reviewed business registration ($details)';
      case 'attraction_status_changed':
        if (target != null && target.isNotEmpty) {
          return details.isEmpty
              ? 'Reviewed attraction registration: $target'
              : 'Reviewed attraction registration: $target ($details)';
        }
        return details.isEmpty
            ? 'Reviewed attraction registration'
            : 'Reviewed attraction registration ($details)';
      case 'guest_record_created':
        return details.isEmpty
            ? 'Created a guest record'
            : 'Created a guest record $details';
      case 'guest_record_updated':
        return details.isEmpty
            ? 'Updated a guest record'
            : 'Updated a guest record: $details';
      case 'guest_record_checked_out':
        return details.isEmpty
            ? 'Checked out a guest'
            : 'Checked out a guest ($details)';
      case 'visit_log_created':
        return details.isEmpty
            ? 'Created a visit log'
            : 'Created a visit log $details';
      case 'profile_updated':
        return details.isEmpty
            ? 'Updated account info'
            : 'Updated account info: $details';
      case 'report_generated':
        return details.isEmpty
            ? 'Generated a report'
            : 'Generated a report: $details';
      default:
        final label = _friendlyLabels[type] ?? type;
        return details.isEmpty ? label : '$label $details';
    }
  }

  Widget _buildWho(ActivityLog log) {
    if (log.actorId == null) {
      return const Text(
        'Unknown',
        style: TextStyle(color: AppColors.textWhite),
      );
    }
    final name = (log.actorName != null && log.actorName!.isNotEmpty)
        ? log.actorName!
        : '';
    final org = log.actorOrgName;
    final role = log.actorRole;
    final line1 = [
      if (name.isNotEmpty) name,
      if (org != null && org.isNotEmpty) org,
      if (role != null && role.isNotEmpty) '($role)',
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line1.isEmpty ? 'Unknown' : line1,
          style: const TextStyle(color: AppColors.textWhite),
        ),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    final result = await showDialog<_DateFilterResult>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      barrierDismissible: true,
      builder: (_) => _DateRangeFilterDialog(
        initialStart: _startDate,
        initialEnd: _endDate,
      ),
    );
    if (result != null) {
      setState(() {
        _startDate = result.start;
        _endDate = result.end;
        _page = 1;
      });
      _fetch();
    }
  }

  Widget _buildFilterBar(bool isNarrow) {
    final dropdown = Container(
      height: 40,
      constraints: isNarrow ? null : const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedActionType,
          isDense: true,
          isExpanded: true,
          menuWidth: isNarrow ? 260 : 320,
          dropdownColor: AppColors.cardBackground,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textGray,
            size: 18,
          ),
          style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5),
          hint: const Text(
            'All action types',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textGray, fontSize: 13.5),
          ),
          selectedItemBuilder: (context) => [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'All action types',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            ..._actionTypes.map(
              (t) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _friendlyLabels[t] ?? t,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ],
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All action types'),
            ),
            ..._actionTypes.map(
              (t) => DropdownMenuItem<String?>(
                value: t,
                child: Text(_friendlyLabels[t] ?? t),
              ),
            ),
          ],
          onChanged: (v) {
            setState(() {
              _selectedActionType = v;
              _page = 1;
            });
            _fetch();
          },
        ),
      ),
    );

    final dateFilter = _DateFilterButton(
      label: _startDate != null && _endDate != null
          ? '${DateFormat('MMM dd, yyyy').format(_startDate!)} - ${DateFormat('MMM dd, yyyy').format(_endDate!)}'
          : 'Date range',
      hasValue: _startDate != null || _endDate != null,
      onTap: _pickDateRange,
    );

    final hasClear = _startDate != null || _selectedActionType != null;
    final clearButton = hasClear
        ? TextButton(
            onPressed: () {
              setState(() {
                _startDate = null;
                _endDate = null;
                _selectedActionType = null;
                _page = 1;
              });
              _fetch();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.textGray),
            child: const Text('Clear'),
          )
        : null;

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: dropdown),
              const SizedBox(width: 8),
              Expanded(child: dateFilter),
            ],
          ),
          if (clearButton != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: clearButton),
          ],
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [dropdown, dateFilter, if (clearButton != null) clearButton],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      title: 'Activity Logs',
      selectedIndex: 5,
      onNavSelected: (_) {},
      child: _error != null
          ? ErrorPage(statusCode: _errorCode ?? 500, onRetry: _fetch)
          : LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 720;
                return SingleChildScrollView(
                  padding: EdgeInsets.all(isNarrow ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _ActivityLogsPageHeader(),
                      const SizedBox(height: 16),
                      // ── Filter bar ──────────────────────────────────────────
                      _buildFilterBar(isNarrow),
                      const SizedBox(height: 20),
                      // ── Table card ────────────────────────────────────────
                      _loading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 48),
                                child: CircularProgressIndicator(
                                  color: AppColors.primaryCyan,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: isNarrow
                                    ? Colors.transparent
                                    : AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isNarrow
                                      ? Colors.transparent
                                      : AppColors.cardBorder,
                                ),
                              ),
                              child: _error != null
                                  ? Center(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: AppColors.accentRed,
                                        ),
                                      ),
                                    )
                                  : _items.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(32),
                                        child: Text(
                                          'No activity logs found.',
                                          style: TextStyle(
                                            color: AppColors.textGray,
                                          ),
                                        ),
                                      ),
                                    )
                                  : LayoutBuilder(
                                      builder: (context, constraints) {
                                        final isNarrow =
                                            constraints.maxWidth < 720;
                                        if (isNarrow) {
                                          return ListView.separated(
                                            padding: EdgeInsets.zero,
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            itemCount: _items.length,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(height: 10),
                                            itemBuilder: (_, i) =>
                                                _ActivityLogCard(
                                                  when: _dateFormat.format(
                                                    _items[i].createdAt
                                                        .toLocal(),
                                                  ),
                                                  who: _buildWho(_items[i]),
                                                  what: _buildSentence(
                                                    _items[i],
                                                  ),
                                                ),
                                          );
                                        }
                                        return SingleChildScrollView(
                                          padding: const EdgeInsets.all(8),
                                          child: Table(
                                            columnWidths: const {
                                              0: FixedColumnWidth(170),
                                              1: FlexColumnWidth(1.4),
                                              2: FlexColumnWidth(2.6),
                                            },
                                            defaultVerticalAlignment:
                                                TableCellVerticalAlignment.top,
                                            border: const TableBorder(
                                              horizontalInside: BorderSide(
                                                color: AppColors.cardBorder,
                                                width: 0.5,
                                              ),
                                            ),
                                            children: [
                                              const TableRow(
                                                children: [
                                                  _ActivityLogHeaderCell(
                                                    'When',
                                                  ),
                                                  _ActivityLogHeaderCell('Who'),
                                                  _ActivityLogHeaderCell(
                                                    'What happened',
                                                  ),
                                                ],
                                              ),
                                              ..._items.map((log) {
                                                return TableRow(
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 14,
                                                          ),
                                                      child: Text(
                                                        _dateFormat.format(
                                                          log.createdAt
                                                              .toLocal(),
                                                        ),
                                                        style: const TextStyle(
                                                          color: AppColors
                                                              .textWhite,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 14,
                                                          ),
                                                      child: _buildWho(log),
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 14,
                                                          ),
                                                      child: Text(
                                                        _buildSentence(log),
                                                        style: const TextStyle(
                                                          color: AppColors
                                                              .textWhite,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              }),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                      if (!_loading && _items.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Paginator(
                            currentPage: _page - 1,
                            totalPages: (_total / _limit).ceil().clamp(
                              1,
                              1000000,
                            ),
                            totalItems: _total,
                            pageSize: _limit,
                            pageSizeOptions: const [10, 20, 50, 100],
                            onPageSizeChanged: (size) {
                              setState(() {
                                _limit = size;
                                _page = 1;
                              });
                              _fetch();
                            },
                            onPageChanged: (p) {
                              setState(() => _page = p + 1);
                              _fetch();
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
// ─── Date filter button ───────────────────────────────────────────────────────

class _DateFilterButton extends StatefulWidget {
  const _DateFilterButton({
    required this.label,
    required this.hasValue,
    required this.onTap,
  });

  final String label;
  final bool hasValue;
  final VoidCallback onTap;

  @override
  State<_DateFilterButton> createState() => _DateFilterButtonState();
}

class _DateFilterButtonState extends State<_DateFilterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.hasValue ? AppColors.primaryCyan : AppColors.textGray;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _hovered
                ? color.withOpacity(0.10)
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered ? color.withOpacity(0.5) : AppColors.cardBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.date_range_rounded, color: color, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: widget.hasValue
                        ? AppColors.primaryCyan
                        : AppColors.textGray,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Compact date range result ────────────────────────────────────────────────

class _DateFilterResult {
  const _DateFilterResult({this.start, this.end});
  final DateTime? start;
  final DateTime? end;
}

// ─── Compact date range dialog ────────────────────────────────────────────────

class _DateRangeFilterDialog extends StatefulWidget {
  const _DateRangeFilterDialog({this.initialStart, this.initialEnd});

  final DateTime? initialStart;
  final DateTime? initialEnd;

  @override
  State<_DateRangeFilterDialog> createState() => _DateRangeFilterDialogState();
}

class _DateRangeFilterDialogState extends State<_DateRangeFilterDialog> {
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.primaryCyan,
            onPrimary: Colors.white,
            surface: AppColors.cardBackground,
            onSurface: AppColors.textWhite,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _end ?? _start ?? now,
      firstDate: _start ?? DateTime(now.year - 5),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.primaryCyan,
            onPrimary: Colors.white,
            surface: AppColors.cardBackground,
            onSurface: AppColors.textWhite,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _end = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primaryCyan.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primaryCyan.withOpacity(0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.date_range_rounded,
                          color: AppColors.primaryCyan,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Select date range',
                              style: TextStyle(
                                color: AppColors.textWhite,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Filter activity logs by date',
                              style: TextStyle(
                                color: AppColors.textGray,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textGray,
                          size: 18,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.cardBorder, height: 1),
                  const SizedBox(height: 20),
                  _DateField(
                    label: 'Start date',
                    value: _start != null
                        ? DateFormat('MMM dd, yyyy').format(_start!)
                        : null,
                    onTap: _pickStart,
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: 'End date',
                    value: _end != null
                        ? DateFormat('MMM dd, yyyy').format(_end!)
                        : null,
                    onTap: _pickEnd,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _ModalButton(
                          label: 'Clear',
                          color: AppColors.textGray,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(const _DateFilterResult()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ModalButton(
                          label: 'Cancel',
                          color: AppColors.textGray,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ModalButton(
                          label: 'Apply',
                          color: AppColors.primaryCyan,
                          filled: true,
                          onTap: () => Navigator.of(
                            context,
                          ).pop(_DateFilterResult(start: _start, end: _end)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.inputBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  color: AppColors.textSubtle,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value ?? 'Select date',
                    style: TextStyle(
                      color: value != null
                          ? AppColors.textWhite
                          : AppColors.textSubtle,
                      fontSize: 13,
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

class _ModalButton extends StatefulWidget {
  const _ModalButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  State<_ModalButton> createState() => _ModalButtonState();
}

class _ModalButtonState extends State<_ModalButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.filled
        ? (_hovered ? widget.color : widget.color.withOpacity(0.85))
        : (_hovered
              ? widget.color.withOpacity(0.15)
              : widget.color.withOpacity(0.08));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.filled
                  ? Colors.transparent
                  : widget.color.withOpacity(_hovered ? 0.5 : 0.25),
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.filled ? Colors.white : widget.color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityLogCard extends StatelessWidget {
  const _ActivityLogCard({
    required this.when,
    required this.who,
    required this.what,
  });

  final String when;
  final Widget who;
  final String what;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 14,
                color: AppColors.textSubtle,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  when,
                  style: const TextStyle(
                    color: AppColors.textSubtle,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          who,
          const SizedBox(height: 8),
          Text(
            what,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Page header ──────────────────────────────────────────────────────────────

class _ActivityLogsPageHeader extends StatelessWidget {
  const _ActivityLogsPageHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Activity Logs',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Track and filter activity performed across the system',
          style: TextStyle(color: AppColors.textGray, fontSize: 13),
        ),
      ],
    );
  }
}

// ─── Table header cell ────────────────────────────────────────────────────────

class _ActivityLogHeaderCell extends StatelessWidget {
  const _ActivityLogHeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textGray,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
