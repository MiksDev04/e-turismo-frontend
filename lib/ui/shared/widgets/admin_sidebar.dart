import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/core/services/session_service.dart';
import 'package:app/router/app_routes.dart';

// ─── Nav Item Model ───────────────────────────────────────────────────────────

class NavItem {
  const NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.route,
  });

  final IconData icon;
  final String label;
  final int index;
  final String route;
}

// ─── Admin Sidebar ────────────────────────────────────────────────────────────

class AdminSidebar extends StatelessWidget {
  const AdminSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

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
      width: 200,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(right: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SidebarBrand(),
          const SizedBox(height: 12),
          _RoleBadge(),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              children: _navItems
                  .map(
                    (item) => _NavTile(
                      item: item,
                      isSelected: selectedIndex == item.index,
                      onTap: () {
                        onItemSelected(item.index);
                        Navigator.pushReplacementNamed(context, item.route);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Brand ────────────────────────────────────────────────────────────────────

class _SidebarBrand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.gradientStart, AppColors.gradientEnd],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text(
                'SP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'San Pablo City',
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Tourism System',
                style: TextStyle(color: AppColors.primaryCyan, fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Role Badge ───────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SessionService.instance,
      builder: (context, _) {
        final role = SessionService.instance.current?.role ?? 'admin';
        final label = role == 'admin' ? 'Tourism Office' : 'Administrator';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryCyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primaryCyan.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryCyan,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.primaryCyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Nav Tile ─────────────────────────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.activeNavBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: AppColors.primaryCyan.withOpacity(0.2))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: isSelected
                      ? AppColors.primaryCyan
                      : AppColors.textGray,
                ),
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.textWhite
                        : AppColors.textGray,
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}