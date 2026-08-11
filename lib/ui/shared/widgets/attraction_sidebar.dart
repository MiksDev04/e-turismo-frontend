import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../router/app_routes.dart';

// ─── Nav Item Model ───────────────────────────────────────────────────────────

class AttrNavItem {
  const AttrNavItem({
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

// ─── Attraction Sidebar ───────────────────────────────────────────────────────

class AttractionSidebar extends StatelessWidget {
  const AttractionSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  List<AttrNavItem> get _navItems => [
        AttrNavItem(
          icon: Icons.dashboard_rounded,
          label: 'Dashboard',
          index: 0,
          route: AppRoutes.attractionDashboard,
        ),
        AttrNavItem(
          icon: Icons.person_add_rounded,
          label: 'Visit Entry',
          index: 1,
          route: AppRoutes.attractionVisitEntry,
        ),
        AttrNavItem(
          icon: Icons.people_alt_rounded,
          label: 'Visit Records',
          index: 2,
          route: AppRoutes.attractionVisitRecord,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(right: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SidebarBrand(),
          const SizedBox(height: 12),
          const _AttractionBadge(),
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
  const _SidebarBrand();

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

// ─── Attraction Badge ─────────────────────────────────────────────────────────

class _AttractionBadge extends StatelessWidget {
  const _AttractionBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.accentGreen.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.accentGreen.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.accentGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Attraction',
              style: TextStyle(
                color: AppColors.accentGreen,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
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

  final AttrNavItem item;
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
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.textWhite
                          : AppColors.textGray,
                      fontSize: 13.5,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
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
