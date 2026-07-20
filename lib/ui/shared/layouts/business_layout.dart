import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../api/messages_api.dart';
import '../widgets/business_sidebar.dart';
import '../widgets/business_header.dart';
import '../../../router/app_routes.dart';

// ─── Business Layout ──────────────────────────────────────────────────────────
//
// Usage:
//   BusinessLayout(
//     title: 'Dashboard',
//     selectedIndex: 0,
//     onNavSelected: (i) { ... },
//     child: YourPageContent(),
//   )

class BusinessLayout extends StatelessWidget {
  const BusinessLayout({
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
        BusinessSidebar(
          selectedIndex: selectedIndex,
          onItemSelected: onNavSelected,
        ),
        Expanded(
          child: Column(
            children: [
              BusinessHeader(
                title: title,
              ),
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
          BusinessHeader(
            title: title,
          ),
          Expanded(
            child: Container(
              color: AppColors.backgroundDark,
              child: child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BusinessBottomNavBar(
        selectedIndex: selectedIndex,
        onItemSelected: onNavSelected,
      ),
    );
  }
}

// ─── Business Bottom Nav Bar (Mobile) ────────────────────────────────────────

class BusinessBottomNavBar extends StatefulWidget {
  const BusinessBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  @override
  State<BusinessBottomNavBar> createState() => _BusinessBottomNavBarState();
}

class _BusinessBottomNavBarState extends State<BusinessBottomNavBar> {
  @override
  void initState() {
    super.initState();
    unawaited(MessageBadgeController.instance.refresh());
  }

  List<BizNavItem> _navItems(int unreadCount) => [
    BizNavItem(
      icon: Icons.dashboard_rounded,
      label: 'Dashboard',
      index: 0,
      route: AppRoutes.businessDashboard,
    ),
    BizNavItem(
      icon: Icons.person_add_rounded,
      label: 'Guest Entry',
      index: 1,
      route: AppRoutes.businessGuestEntry,
    ),
    BizNavItem(
      icon: Icons.people_alt_rounded,
      label: 'Guest Records',
      index: 2,
      route: AppRoutes.businessGuestRecord,
    ),
    BizNavItem(
      icon: Icons.meeting_room_outlined,
      label: 'Rooms',
      index: 3,
      route: AppRoutes.businessRooms,
    ),
    BizNavItem(
      icon: Icons.chat_bubble_outline_rounded,
      label: 'Messages',
      index: 5,
      badge: unreadCount > 0 ? unreadCount : null,
      route: AppRoutes.businessMessages,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MessageBadgeController.instance.unreadCount,
      builder: (context, unreadCount, _) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.sidebarBg,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
          ),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _navItems(unreadCount).map((item) {
                final isSelected = widget.selectedIndex == item.index;
                return _BottomNavTile(
                  item: item,
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

// ─── Bottom Nav Tile ──────────────────────────────────────────────────────────

class _BottomNavTile extends StatelessWidget {
  const _BottomNavTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final BizNavItem item;
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
                  if (item.badge != null)
                    Positioned(
                      top: -4,
                      right: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryCyan,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '${item.badge}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primaryCyan
                      : AppColors.textGray,
                  fontSize: 11,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}