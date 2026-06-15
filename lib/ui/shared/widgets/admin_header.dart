import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/session_service.dart';
import 'logout_confirm_dialog.dart';
import '../../../router/app_routes.dart';

// ─── Admin Header ─────────────────────────────────────────────────────────────

class AdminHeader extends StatelessWidget implements PreferredSizeWidget {
  const AdminHeader({super.key, required this.title});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return ListenableBuilder(
      listenable: SessionService.instance,
      builder: (context, _) {
        final session = SessionService.instance.current;
        return Container(
          height: isMobile ? 48 : 56,
          decoration: const BoxDecoration(
            color: AppColors.backgroundMid,
            border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
          ),
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: [
                  _LogoutButton(
                    onTap: () => showLogoutConfirmDialog(context),
                    compact: isMobile,
                  ),
                  SizedBox(width: isMobile ? 6 : 8),
                  Container(
                      width: 1, height: isMobile ? 18 : 24, color: AppColors.cardBorder),
                  SizedBox(width: isMobile ? 8 : 12),
                  _ProfileButton(
                    displayName: session?.fullName ?? '—',
                    initials: session?.initials ?? '?',
                    compact: isMobile,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogoutButton extends StatefulWidget {
  const _LogoutButton({required this.onTap, required this.compact});

  final VoidCallback onTap;
  final bool compact;

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.all(widget.compact ? 6 : 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _isHovered
                ? AppColors.cardBorder.withOpacity(0.3)
                : Colors.transparent,
          ),
          child: const Icon(
            Icons.logout_rounded,
            color: AppColors.textGray,
            size: 18,
          ),
        ),
      ),
    );
  }
}


class _ProfileButton extends StatefulWidget {
  const _ProfileButton({
    required this.displayName,
    required this.initials,
    required this.compact,
  });

  final String displayName;
  final String initials;
  final bool compact;

  @override
  State<_ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends State<_ProfileButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          Navigator.pushReplacementNamed(context, AppRoutes.adminProfile),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 4 : 8,
            vertical: widget.compact ? 2 : 4,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _isHovered 
                ? AppColors.cardBorder.withOpacity(0.3)
                : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: widget.compact ? 26 : 30,
                height: widget.compact ? 26 : 30,
                decoration: const BoxDecoration(
                  color: AppColors.primaryCyan,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.initials,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!widget.compact) ...[
                const SizedBox(width: 8),
                Text(
                  widget.displayName,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}