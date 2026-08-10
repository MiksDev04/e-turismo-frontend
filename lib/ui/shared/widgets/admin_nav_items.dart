import 'package:flutter/material.dart';
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

// ─── Admin Nav Items ─────────────────────────────────────────────────────────
//
// Single source of truth shared by AdminSidebar (desktop) and
// AdminBottomNavBar (mobile) so indices/routes can't drift apart.

abstract final class AdminNavItems {
  static const List<NavItem> items = [
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
      icon: Icons.attractions_rounded,
      label: 'Attractions',
      index: 2,
      route: AppRoutes.adminAttractions,
    ),
    NavItem(
      icon: Icons.bar_chart_rounded,
      label: 'Report',
      index: 3,
      route: AppRoutes.adminReports,
    ),
    NavItem(
      icon: Icons.chat_bubble_outline_rounded,
      label: 'Messages',
      index: 4,
      route: AppRoutes.adminMessages,
    ),
    NavItem(
      icon: Icons.shield_outlined,
      label: 'Compliance',
      index: 5,
      route: AppRoutes.adminCompliance,
    ),
  ];

  /// Profile is only reachable via the header, so it is not part of the
  /// sidebar/bottom nav — but it keeps a reserved index for highlight logic.
  static const int profileIndex = 6;
}
