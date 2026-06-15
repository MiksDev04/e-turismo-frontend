// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../api/admin_compliance_api.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _monthNames = [
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

// CHANGED: Moved 'Sun' to the front
const _shortDayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

// ─── Widget ───────────────────────────────────────────────────────────────────

class BusinessTouristStatsModal extends StatefulWidget {
  const BusinessTouristStatsModal({
    super.key,
    required this.businessId,
    required this.businessName,
  });

  final String businessId;
  final String businessName;

  @override
  State<BusinessTouristStatsModal> createState() =>
      _BusinessTouristStatsModalState();
}

class _BusinessTouristStatsModalState extends State<BusinessTouristStatsModal> {
  // ── State ──────────────────────────────────────────────────────────────────
  late int _selectedMonth;
  late int _selectedYear;

  List<DailyGuestStat> _stats = [];
  bool _isLoading = false;
  String? _error;

  List<int> get _availableYears {
    final current = DateTime.now().year;
    return List.generate(current - 2019, (i) => current - i);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = now.month;
    _selectedYear = now.year;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final stats = await AdminComplianceApi().fetchDailyStats(
        widget.businessId,
        _selectedMonth,
        _selectedYear,
      );
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } on SocketException {
      if (mounted) {
        setState(() {
          _error = 'Network error. Please check your connection.';
          _isLoading = false;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _error = 'Request timed out. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  int get _grandTotal => _stats.fold(0, (sum, s) => sum + s.totalGuests);

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Detect mobile screens to adjust padding & spacing
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 500;
    
    // Reduce dialog padding on small screens to give the grid more room
    final dialogInset = isMobile ? 16.0 : 40.0;
    final contentPadding = isMobile ? 16.0 : 24.0;

    return Dialog(
      backgroundColor: AppColors.cardBackground,
      insetPadding: EdgeInsets.symmetric(horizontal: dialogInset, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85, 
        ),
        child: Padding(
          padding: EdgeInsets.all(contentPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              const Divider(color: AppColors.cardBorder, height: 1),
              const SizedBox(height: 16),
              _buildFilters(),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: _buildBody(isMobile),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accentGreen.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.calendar_month_rounded,
            color: AppColors.accentGreen,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tourist Statistics',
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.businessName,
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded, size: 18),
          color: AppColors.textGray,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  // ── Filters ────────────────────────────────────────────────────────────────
  Widget _buildFilters() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _StatsDropdown(
            value: _monthNames[_selectedMonth - 1],
            items: _monthNames,
            onChanged: (v) {
              final idx = _monthNames.indexOf(v!);
              setState(() => _selectedMonth = idx + 1);
              _load();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _StatsDropdown(
            value: '$_selectedYear',
            items: _availableYears.map((y) => '$y').toList(),
            onChanged: (v) {
              setState(() => _selectedYear = int.parse(v!));
              _load();
            },
          ),
        ),
      ],
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody(bool isMobile) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: CircularProgressIndicator(
            color: AppColors.primaryCyan,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: AppColors.textSubtle,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.textGray, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Retry', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryCyan,
                  side: BorderSide(
                    color: AppColors.primaryCyan.withOpacity(0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildCalendar(isMobile);
  }

  // ── Calendar View ──────────────────────────────────────────────────────────
  Widget _buildCalendar(bool isMobile) {
    final int daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final int firstWeekday = DateTime(_selectedYear, _selectedMonth, 1).weekday;
    
    // CHANGED: DateTime.weekday returns 1 for Mon, 7 for Sun. 
    // If it's Sunday (7), we want 0 empty slots before it. Otherwise, offset by the weekday number.
    final int emptySlots = firstWeekday == 7 ? 0 : firstWeekday; 
    
    final int totalCells = daysInMonth + emptySlots;

    final double gridSpacing = isMobile ? 4.0 : 8.0;
    final double gridPadding = isMobile ? 8.0 : 12.0;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Day of Week Headers ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _shortDayNames
                  .map(
                    (day) => Expanded(
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textGray,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          
          // ── Calendar Grid ──────────────────────────────────────────────────
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.all(gridPadding),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: gridSpacing,
              crossAxisSpacing: gridSpacing,
              childAspectRatio: 1.0,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              if (index < emptySlots) {
                return const SizedBox.shrink();
              }

              final day = index - emptySlots + 1;
              final statIndex = _stats.indexWhere((s) => s.date.day == day);
              final guests = statIndex >= 0 ? _stats[statIndex].totalGuests : 0;
              final hasData = guests > 0;

              return Container(
                decoration: BoxDecoration(
                  color: hasData
                      ? AppColors.primaryCyan.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasData
                        ? AppColors.primaryCyan.withOpacity(0.5)
                        : AppColors.cardBorder.withOpacity(0.4),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            color: hasData
                                ? AppColors.textWhite
                                : AppColors.textSubtle,
                            fontSize: 11,
                            fontWeight:
                                hasData ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (hasData) const SizedBox(height: 2),
                        if (hasData)
                          Text(
                            '$guests',
                            style: const TextStyle(
                              color: AppColors.primaryCyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          
          // ── Grand Total Footer ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.cardBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    isMobile ? 'Monthly Total' : 'Total Guests this Month',
                    style: const TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '$_grandTotal',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppColors.primaryCyan,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
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
}

// ─── Dropdown ─────────────────────────────────────────────────────────────────

class _StatsDropdown extends StatelessWidget {
  const _StatsDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = items.contains(value) ? value : items.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          isDense: true,
          dropdownColor: AppColors.cardBackground,
          iconEnabledColor: AppColors.textGray,
          style: const TextStyle(color: AppColors.textGray, fontSize: 13),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}