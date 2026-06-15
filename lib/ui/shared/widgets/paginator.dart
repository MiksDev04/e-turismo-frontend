
import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';

// ─── Paginator ────────────────────────────────────────────────────────────────

class Paginator extends StatelessWidget {
  const Paginator({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.pageSize,
    required this.pageSizeOptions,
    required this.onPageSizeChanged,
    required this.onPageChanged,
  });

  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int pageSize;
  final List<int> pageSizeOptions;
  final ValueChanged<int> onPageSizeChanged;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final start = totalItems == 0 ? 0 : currentPage * pageSize + 1;
    final end = ((currentPage + 1) * pageSize).clamp(0, totalItems);
    final visiblePages = _visiblePages(currentPage, totalPages);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;

        final infoRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$start–$end of $totalItems',
              style: const TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
            const SizedBox(width: 12),
            const Text(
              'Rows',
              style: TextStyle(color: AppColors.textGray, fontSize: 12),
            ),
            const SizedBox(width: 8),
            _PageSizeDropdown(
              value: pageSize,
              options: pageSizeOptions,
              onChanged: onPageSizeChanged,
            ),
          ],
        );

        final pagerRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PageBtn(
              icon: Icons.chevron_left_rounded,
              enabled: currentPage > 0,
              onTap: () => onPageChanged(currentPage - 1),
            ),
            const SizedBox(width: 4),
            for (final i in visiblePages)
              _PageNumber(
                page: i,
                isActive: i == currentPage,
                onTap: () => onPageChanged(i),
              ),
            const SizedBox(width: 4),
            _PageBtn(
              icon: Icons.chevron_right_rounded,
              enabled: currentPage < totalPages - 1,
              onTap: () => onPageChanged(currentPage + 1),
            ),
          ],
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              infoRow,
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: pagerRow,
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [infoRow, pagerRow],
        );
      },
    );
  }


  static List<int> _visiblePages(int current, int total) {
    if (total <= 5) {
      return List<int>.generate(total, (index) => index);
    }

    var start = current - 2;
    var end = current + 2;

    if (start < 0) {
      end += -start;
      start = 0;
    }

    if (end > total - 1) {
      start -= end - (total - 1);
      end = total - 1;
    }

    start = start.clamp(0, total - 5);
    end = (start + 4).clamp(4, total - 1);

    return [for (int i = start; i <= end; i++) i];
  }
}

class _PageSizeDropdown extends StatelessWidget {
  const _PageSizeDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          dropdownColor: AppColors.cardBackground,
          iconEnabledColor: AppColors.textGray,
          style: const TextStyle(color: AppColors.textGray, fontSize: 12),
          items: options
              .map(
                (option) => DropdownMenuItem<int>(
                  value: option,
                  child: Text('$option'),
                ),
              )
              .toList(),
          onChanged: (selected) {
            if (selected != null) {
              onChanged(selected);
            }
          },
        ),
      ),
    );
  }
}

class _PageBtn extends StatelessWidget {
  const _PageBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.textGray : AppColors.textSubtle,
        ),
      ),
    );
  }
}

class _PageNumber extends StatelessWidget {
  const _PageNumber({
    required this.page,
    required this.isActive,
    required this.onTap,
  });

  final int page;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.accentGreen.withOpacity(0.15)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: isActive
                ? AppColors.accentGreen.withOpacity(0.5)
                : AppColors.cardBorder,
          ),
        ),
        child: Center(
          child: Text(
            '${page + 1}',
            style: TextStyle(
              color: isActive ? AppColors.accentGreen : AppColors.textGray,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
