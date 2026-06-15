import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/ui/shared/widgets/admin_sidebar.dart';
import 'package:app/ui/shared/widgets/admin_header.dart';
import 'package:app/router/app_routes.dart';
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

class AdminBottomNavBar extends StatelessWidget {
  const AdminBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;


  // Reuse the same nav items from AdminSidebar
  static const _navItems = [
    NavItem(
      icon: Icons.dashboard_rounded,
      label: 'Dashboard',
      index: 0,
      route: AppRoutes.adminDashboard,
    ),
    NavItem(
      icon: Icons.apartment_rounded,
      label: 'Accommodations',
      index: 1,
      route: AppRoutes.adminAccommodations,
    ),
    NavItem(
      icon: Icons.bar_chart_rounded,
      label: 'Report',
      index: 2,
      route: AppRoutes.adminReports,
    ),
    NavItem(
      icon: Icons.chat_bubble_outline_rounded,
      label: 'Messages',
      index: 3,
      route: AppRoutes.adminMessages,
    ),
    NavItem(
      icon: Icons.shield_outlined,
      label: 'Compliance',
      index: 4,
      route: AppRoutes.adminCompliance,
    ),
  ];

  @override
  Widget build(BuildContext context) {

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
          children: _navItems.map((item) {
            final isSelected = selectedIndex == item.index;
            return _BottomNavTile(
              item: item,
              isSelected: isSelected,
              onTap: () {
                onItemSelected(item.index);
                Navigator.pushReplacementNamed(context, item.route);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _BottomNavTile extends StatelessWidget {
  const _BottomNavTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final NavItem item;
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
              Icon(
                item.icon,
                size: 22,
                color: isSelected
                    ? AppColors.primaryCyan
                    : AppColors.textGray,
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