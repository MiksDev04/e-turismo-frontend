import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../widgets/attraction_sidebar.dart';
import '../widgets/attraction_header.dart';
import '../../../router/app_routes.dart';

// ─── Attraction Layout ────────────────────────────────────────────────────────
//
// Usage:
//   AttractionLayout(
//     title: 'Dashboard',
//     selectedIndex: 0,
//     onNavSelected: (i) { ... },
//     child: YourPageContent(),
//   )

class AttractionLayout extends StatelessWidget {
  const AttractionLayout({
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
        AttractionSidebar(
          selectedIndex: selectedIndex,
          onItemSelected: onNavSelected,
        ),
        Expanded(
          child: Column(
            children: [
              AttractionHeader(title: title),
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
          AttractionHeader(title: title),
          Expanded(
            child: Container(
              color: AppColors.backgroundDark,
              child: child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: AttractionBottomNavBar(
        selectedIndex: selectedIndex,
        onItemSelected: onNavSelected,
      ),
    );
  }
}

// ─── Attraction Bottom Nav Bar (Mobile) ───────────────────────────────────────

class AttractionBottomNavBar extends StatelessWidget {
  const AttractionBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
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
        icon: Icons.list_rounded,
        label: 'Records',
        index: 2,
        route: AppRoutes.attractionVisitRecord,
      ),
      AttrNavItem(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'Messages',
        index: 3,
        route: AppRoutes.attractionMessages,
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: items.map((item) {
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

// ─── Bottom Nav Tile ──────────────────────────────────────────────────────────

class _BottomNavTile extends StatelessWidget {
  const _BottomNavTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final AttrNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
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
                item.label,
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
