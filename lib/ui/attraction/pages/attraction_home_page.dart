import 'package:flutter/material.dart';
import 'package:app/core/services/session_service.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/ui/shared/widgets/logout_confirm_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Tourist Attraction Home (minimal landing page)
//
//  Temporary landing page for approved attraction accounts until the full
//  attraction portal (visit logging, messages, profile) is built.
// ─────────────────────────────────────────────────────────────────────────────

class AttractionHomePage extends StatelessWidget {
  const AttractionHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionService.instance.current;
    final attractionName =
        (session?.attractionName?.trim().isNotEmpty ?? false)
            ? session!.attractionName!
            : session?.fullName ?? 'Tourist Attraction';

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            _AttractionHeader(onLogout: () => showLogoutConfirmDialog(context)),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.cardBorder, width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 40,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.primaryCyan.withOpacity(0.08),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primaryCyan.withOpacity(0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.attractions_rounded,
                              color: AppColors.primaryCyan,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            attractionName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textWhite,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Approved Account',
                            style: TextStyle(
                              color: AppColors.primaryCyan,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.inputBackground,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.inputBorder,
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.construction_rounded,
                                  color: AppColors.textGray,
                                  size: 18,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'The tourist attraction portal is under '
                                    'construction. Visit logging and other '
                                    'tools will be available here soon.',
                                    style: TextStyle(
                                      color: AppColors.textGray,
                                      fontSize: 12.5,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttractionHeader extends StatelessWidget {
  const _AttractionHeader({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.attractions_rounded,
            color: AppColors.primaryCyan,
            size: 24,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Tourist Attraction',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: onLogout,
            icon: const Icon(
              Icons.logout_rounded,
              color: AppColors.textGray,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}
