import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/api/admin_dashboard_api.dart';
import 'package:app/ui/shared/widgets/admin_sidebar.dart';
import 'package:app/ui/shared/widgets/admin_header.dart';
import 'package:app/ui/shared/widgets/admin_nav_items.dart';

int? _badgeForIndex(int index, PendingCounts counts) => switch (index) {
  1 => counts.pendingAccommodations > 0 ? counts.pendingAccommodations : null,
  2 => counts.pendingAttractions > 0 ? counts.pendingAttractions : null,
  _ => null,
};

// ─── Admin Layout ─────────────────────────────────────────────────────────────
//
// Usage:
//   AdminLayout(
//     title: 'Dashboard',
//     selectedIndex: 0,
//     onNavSelected: (i) { ... },
//     child: YourPageContent(),
//   )

class AdminLayout extends StatelessWidget {
  const AdminLayout({
    super.key,
    required this.title,
    required this.selectedIndex,
    required this.onNavSelected,
    required this.child,
  });

  final String title;
  final int selectedIndex;
  final ValueChanged<int> onNavSelected;
  final Widget child;

  final String displayName = 'Tourism Office';
  final String initials = 'TO';

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        bottom: false,
        child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        AdminSidebar(
          selectedIndex: selectedIndex,
          onItemSelected: onNavSelected,
        ),
        Expanded(
          child: Column(
            children: [
              AdminHeader(title: title),
              Expanded(
                child: Container(color: AppColors.backgroundDark, child: child),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Column(
        children: [
          AdminHeader(title: title),
          Expanded(
            child: Container(color: AppColors.backgroundDark, child: child),
          ),
        ],
      ),
      bottomNavigationBar: AdminBottomNavBar(
        selectedIndex: selectedIndex,
        onItemSelected: onNavSelected,
      ),
    );
  }
}

// ─── Admin Bottom Nav Bar (Mobile) ────────────────────────────────────────────

class AdminBottomNavBar extends StatefulWidget {
  const AdminBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  @override
  State<AdminBottomNavBar> createState() => _AdminBottomNavBarState();
}

class _AdminBottomNavBarState extends State<AdminBottomNavBar> {
  @override
  void initState() {
    super.initState();
    unawaited(PendingBadgeController.instance.refresh());
  }

  int? _badgeFor(int index, PendingCounts counts) =>
      _badgeForIndex(index, counts);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PendingCounts>(
      valueListenable: PendingBadgeController.instance.counts,
      builder: (context, counts, _) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sidebarBg,
            border: const Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ...AdminNavItems.items.take(4).map((item) {
                  final isSelected = widget.selectedIndex == item.index;
                  return _BottomNavTile(
                    item: item,
                    badge: _badgeFor(item.index, counts),
                    isSelected: isSelected,
                    onTap: () {
                      widget.onItemSelected(item.index);
                      Navigator.pushReplacementNamed(context, item.route);
                    },
                  );
                }),
                _MoreNavButton(
                  moreItems: AdminNavItems.items.skip(4).toList(),
                  counts: counts,
                  selectedIndex: widget.selectedIndex,
                  onSelected: (item) {
                    widget.onItemSelected(item.index);
                    Navigator.pushReplacementNamed(context, item.route);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BottomNavTile extends StatelessWidget {
  const _BottomNavTile({
    required this.item,
    required this.badge,
    required this.isSelected,
    required this.onTap,
  });

  final NavItem item;
  final int? badge;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    item.icon,
                    size: 22,
                    color: isSelected
                        ? AppColors.primaryCyan
                        : AppColors.textGray,
                  ),
                  if (badge != null)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryCyan,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(minWidth: 16),
                        child: Text(
                          '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                (item.label == 'Accommodations' && isMobile)
                    ? 'Accom'
                    : item.label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primaryCyan
                      : AppColors.textGray,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── More Nav Button (Mobile) ─────────────────────────────────────────────────

class _MoreNavButton extends StatelessWidget {
  const _MoreNavButton({
    required this.moreItems,
    required this.counts,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<NavItem> moreItems;
  final PendingCounts counts;
  final int selectedIndex;
  final ValueChanged<NavItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final isSelected = moreItems.any((item) => selectedIndex == item.index);

    int? moreBadge;
    var badgeSum = 0;
    var hasBadge = false;
    for (final item in moreItems) {
      final badge = _badgeForIndex(item.index, counts);
      if (badge != null) {
        hasBadge = true;
        badgeSum += badge;
      }
    }
    if (hasBadge) moreBadge = badgeSum;

    return PopupMenuButton<NavItem>(
      padding: EdgeInsets.zero,
      tooltip: 'More',
      offset: Offset.zero,
      color: AppColors.sidebarBg,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => moreItems.map((item) {
        final itemSelected = selectedIndex == item.index;
        final badge = _badgeForIndex(item.index, counts);
        return PopupMenuItem<NavItem>(
          value: item,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 20,
                color: itemSelected
                    ? AppColors.primaryCyan
                    : AppColors.textGray,
              ),
              const SizedBox(width: 10),
              Text(
                item.label,
                style: TextStyle(
                  color: itemSelected
                      ? AppColors.textWhite
                      : AppColors.textGray,
                  fontSize: 13.5,
                  fontWeight: itemSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (badge != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryCyan,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(
                    '$badge',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.more_horiz_rounded,
                  size: 22,
                  color: isSelected
                      ? AppColors.primaryCyan
                      : AppColors.textGray,
                ),
                if (moreBadge != null)
                  Positioned(
                    right: -8,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryCyan,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      child: Text(
                        '$moreBadge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'More',
              style: TextStyle(
                color: isSelected ? AppColors.primaryCyan : AppColors.textGray,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
