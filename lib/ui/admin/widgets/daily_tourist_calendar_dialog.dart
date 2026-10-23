// lib/ui/admin/widgets/daily_tourist_calendar_dialog.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../models/daily_tourist_models.dart';

/// Shows a calendar dialog displaying per-day tourist/visitor counts for a
/// given entity (accommodation or attraction) over a selected month/year.
///
/// [fetch] is called with (month, year) and should return the result for that
/// period. Returning null indicates an error and the dialog will show an
/// error state with a Retry button.
Future<void> showDailyTouristCalendarDialog({
  required BuildContext context,
  required String title,
  required Future<DailyTouristsResult?> Function(int month, int year) fetch,
  int? initialYear,
  int? initialMonth,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    barrierDismissible: true,
    builder: (dialogContext) {
      return _DailyTouristCalendarDialog(
        title: title,
        fetch: fetch,
        initialYear: initialYear ?? DateTime.now().year,
        initialMonth: initialMonth ?? DateTime.now().month,
      );
    },
  );
}

class _DailyTouristCalendarDialog extends StatefulWidget {
  const _DailyTouristCalendarDialog({
    required this.title,
    required this.fetch,
    required this.initialYear,
    required this.initialMonth,
  });

  final String title;
  final Future<DailyTouristsResult?> Function(int month, int year) fetch;
  final int initialYear;
  final int initialMonth;

  @override
  State<_DailyTouristCalendarDialog> createState() =>
      _DailyTouristCalendarDialogState();
}

class _DailyTouristCalendarDialogState
    extends State<_DailyTouristCalendarDialog>
    with SingleTickerProviderStateMixin {
  static const int _minYear = 2000;

  /// Future years can never hold records, so the picker stops at this year.
  int get _maxYear => DateTime.now().year;

  late int _month;
  late int _year;

  bool _loading = false;
  bool _error = false;
  DailyTouristsResult? _result;

  int _requestId = 0;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  /// The real "now", used to mark today's cell.
  DateTime get _now => DateTime.now();

  /// Whether the month currently shown in the calendar is the current month.
  bool get _isCurrentMonth => _year == _now.year && _month == _now.month;

  final List<String> _monthNames = const [
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

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();

    _month = widget.initialMonth.clamp(1, 12);
    _year = widget.initialYear.clamp(_minYear, _maxYear);
    _load();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = false;
    });

    final result = await widget.fetch(_month, _year);

    if (!mounted) return;
    if (requestId != _requestId) {
      return;
    }

    setState(() {
      _loading = false;
      if (result == null) {
        _error = true;
        _result = null;
      } else {
        _error = false;
        _result = result;
      }
    });
  }

  void _onMonthChanged(int? value) {
    if (value == null) return;
    if (value == _month) return;
    setState(() {
      _month = value;
    });
    _load();
  }

  void _onYearChanged(int? value) {
    if (value == null) return;
    if (value == _year) return;
    setState(() {
      _year = value;
    });
    _load();
  }

  String get _monthLabel {
    if (_month < 1 || _month > 12) return '';
    return _monthNames[_month - 1];
  }

  int get _daysInMonth {
    if (_result != null && _result!.year == _year && _result!.month == _month) {
      return _result!.daysInMonth;
    }
    return DateTime(_year, _month + 1, 0).day;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth >= 640 ? 560.0 : 420.0;

    // The dialog route does not provide a Material ancestor, but Material
    // widgets such as DropdownButton require one.
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen tap catcher: a tap outside the card closes the dialog.
          // The card is painted on top of this layer, so taps inside the card
          // never reach it.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DialogHeader(
                          title: widget.title,
                          onClose: () => Navigator.of(context).pop(),
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: _Dropdown(
                                  value: _month,
                                  items: List.generate(12, (index) {
                                    final monthValue = index + 1;
                                    return DropdownMenuItem<int>(
                                      value: monthValue,
                                      child: Text(
                                        _monthNames[index],
                                        style: const TextStyle(
                                          color: AppColors.textWhite,
                                          fontSize: 13,
                                        ),
                                      ),
                                    );
                                  }),
                                  onChanged: _loading ? null : _onMonthChanged,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _Dropdown(
                                  value: _year,
                                  items: List.generate(
                                    _maxYear - _minYear + 1,
                                    (index) {
                                      final yearValue = _minYear + index;
                                      return DropdownMenuItem<int>(
                                        value: yearValue,
                                        child: Text(
                                          yearValue.toString(),
                                          style: const TextStyle(
                                            color: AppColors.textWhite,
                                            fontSize: 13,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  onChanged: _loading ? null : _onYearChanged,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: _buildBody(),
                          ),
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        _TotalFooter(
                          monthLabel: _monthLabel,
                          year: _year,
                          total: _result?.total ?? 0,
                          isLoading: _loading,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // A result is only usable when it belongs to the currently selected period;
    // otherwise the previous month would be drawn under the new month's days.
    final result = _result;
    final resultMatches =
        result != null && result.year == _year && result.month == _month;

    if (_loading && !resultMatches) {
      return const SizedBox(
        height: 220,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryCyan,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_error && !resultMatches) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.accentOrange,
                size: 32,
              ),
              const SizedBox(height: 10),
              const Text(
                'Failed to load daily tourist records.',
                style: TextStyle(color: AppColors.textGray, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppColors.primaryCyan,
                ),
                label: const Text(
                  'Retry',
                  style: TextStyle(
                    color: AppColors.primaryCyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!resultMatches) {
      return const SizedBox(height: 220);
    }

    final daysInMonth = _daysInMonth;

    // The 1st of the month falls on a weekday; blank cells are added before it
    // so every date lines up under the right weekday column.
    final leadingCells = DateTime(_year, _month, 1).weekday % 7;
    final trailingCells =
        (7 - ((leadingCells + daysInMonth) % 7)) % 7;
    final cellCount = leadingCells + daysInMonth + trailingCells;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.primaryCyan,
              backgroundColor: AppColors.cardBorder,
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _WeekdayHeader(),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.0,
                      ),
                  itemCount: cellCount,
                  itemBuilder: (context, index) {
                    if (index < leadingCells) return const SizedBox.shrink();
                    final day = index - leadingCells + 1;
                    if (day > daysInMonth) return const SizedBox.shrink();
                    final count = result.countFor(day);
                    // Only the real current date carries the "Today" pill, and
                    // only while the current month is on screen.
                    final isToday = _isCurrentMonth && day == _now.day;
                    return _DayCell(
                      day: day,
                      count: count,
                      isToday: isToday,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_month_rounded,
            color: AppColors.accentPurple,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _HoverIconButton(icon: Icons.close_rounded, onTap: onClose),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final int value;
  final List<DropdownMenuItem<int>> items;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: AppColors.cardBackground,
          menuMaxHeight: 240,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 13,
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textGray,
            size: 18,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const List<String> _labels = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < _labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Center(
              child: Text(
                _labels[i],
                style: const TextStyle(
                  color: AppColors.textSubtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.day,
    required this.count,
    required this.isToday,
  });

  final int day;
  final int count;

  /// Whether this cell is the real current date.
  final bool isToday;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  /// How far the diagonal "Today" tag reaches past the cell corner.
  static const double _cornerOffset = 10;

  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final count = widget.count;
    final isToday = widget.isToday;
    final hasData = count > 0;

    // Hovering lifts the accent; today's cell keeps its orange identity.
    final Color borderColor;
    final Color background;
    if (isToday) {
      borderColor = AppColors.accentOrange;
      background = AppColors.accentOrange.withOpacity(_hovered ? 0.18 : 0.10);
    } else if (_hovered) {
      borderColor = AppColors.primaryCyan.withOpacity(0.95);
      background = hasData
          ? AppColors.primaryCyan.withOpacity(0.20)
          : AppColors.inputBackground;
    } else {
      borderColor = hasData
          ? AppColors.primaryCyan.withOpacity(0.40)
          : AppColors.inputBorder;
      background = hasData
          ? AppColors.primaryCyan.withOpacity(0.12)
          : AppColors.inputBackground;
    }

    final dayText = Text(
      day.toString(),
      style: TextStyle(
        color: hasData ? AppColors.textWhite : AppColors.textGray,
        fontSize: 11,
        fontWeight: hasData ? FontWeight.w600 : FontWeight.w500,
      ),
    );

    final countText = Text(
      count.toString(),
      style: TextStyle(
        color: hasData ? AppColors.primaryCyan : AppColors.textSubtle,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        // Swallow the tap so the outside-tap layer never closes the dialog.
        onTap: () {},
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
          ),
          // Painted on top of the content so the diagonal tag of today's
          // cell cannot cover the border.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: borderColor,
              width: isToday ? 1.6 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              dayText,
                              const SizedBox(height: 2),
                              countText,
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isToday)
                      Positioned(
                        left: constraints.maxWidth -
                            _TodayBadge.width / 2 -
                            _cornerOffset,
                        top: constraints.maxHeight -
                            _TodayBadge.height / 2 -
                            _cornerOffset,
                        child: Transform.rotate(
                          angle: -math.pi / 4,
                          child: const _TodayBadge(),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// Diagonal corner tag that marks the current date.
class _TodayBadge extends StatelessWidget {
  const _TodayBadge();

  /// Fixed size so the tag can be centred on the cell corner precisely.
  static const double width = 30;
  static const double height = 14;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accentOrange,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.5, vertical: 2.5),
          child: Text(
            'Today',
            style: TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalFooter extends StatelessWidget {
  const _TotalFooter({
    required this.monthLabel,
    required this.year,
    required this.total,
    required this.isLoading,
  });

  final String monthLabel;
  final int year;
  final int total;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        children: [
          Text(
            'Total for $monthLabel $year:',
            style: const TextStyle(color: AppColors.textGray, fontSize: 13),
          ),
          const Spacer(),
          if (isLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryCyan,
              ),
            )
          else
            Text(
              '$total tourist${total == 1 ? '' : 's'}',
              style: const TextStyle(
                color: AppColors.primaryCyan,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _HoverIconButton extends StatefulWidget {
  const _HoverIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.cardBorder.withOpacity(0.6)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            widget.icon,
            color: _hovered ? AppColors.textWhite : AppColors.textGray,
            size: 18,
          ),
        ),
      ),
    );
  }
}
