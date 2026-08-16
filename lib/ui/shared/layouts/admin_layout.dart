import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/api/admin_dashboard_api.dart';
import 'package:app/ui/shared/widgets/admin_sidebar.dart';
import 'package:app/ui/shared/widgets/admin_header.dart';
import 'package:app/ui/shared/widgets/admin_nav_items.dart';
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
      body: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
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
                child: Container(
                  color: AppColors.backgroundDark,
                  child: child,
                ),
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
            child: Container(
              color: AppColors.backgroundDark,
              child: child,
            ),
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

  int? _badgeFor(int index, PendingCounts counts) => switch (index) {
    1 => counts.pendingAccommodations > 0 ? counts.pendingAccommodations : null,
    2 => counts.pendingAttractions > 0 ? counts.pendingAttractions : null,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PendingCounts>(
      valueListenable: PendingBadgeController.instance.counts,
      builder: (context, counts, _) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.sidebarBg,
            border: const Border(
              top: BorderSide(color: AppColors.cardBorder),
            ),
          ),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: AdminNavItems.items.map((item) {
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
              }).toList(),
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
                (item.label == 'Accommodations' && isMobile) ? 'Accom' : item.label,
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