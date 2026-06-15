// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/session_service.dart';
import '../../../router/app_routes.dart';

// =============================================================================
// PUBLIC HELPER
// =============================================================================

/// Shows the logout confirmation dialog.
/// If the user confirms, clears the session and navigates to [AppRoutes.login].
Future<void> showLogoutConfirmDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _LogoutConfirmDialog(),
  );

  if (confirmed == true && context.mounted) {
    await SessionService.instance.clear();
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }
}

// =============================================================================
// DIALOG WIDGET (private)
// =============================================================================

class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ────────────────────────────────────────────────────────
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.accentRed.withOpacity(0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accentRed.withOpacity(0.20),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.accentRed,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),

              // ── Title ───────────────────────────────────────────────────────
              const Text(
                'Log Out',
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),

              // ── Body ────────────────────────────────────────────────────────
              const Text(
                'Are you sure you want to log out\nof your account?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textGray,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 24),

              // ── Divider ─────────────────────────────────────────────────────
              Container(height: 1, color: AppColors.cardBorder),
              const SizedBox(height: 16),

              // ── Buttons ─────────────────────────────────────────────────────
              Row(
                children: [
                  // Cancel
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.cardBorder),
                        foregroundColor: AppColors.textGray,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Log Out (destructive)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      child: const Text(
                        'Log Out',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}