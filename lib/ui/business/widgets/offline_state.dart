import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/connectivity_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  OfflineState
//
//  Shown whenever a page detects no internet during a load attempt.
//  Displays a pulsing "Listening for connection…" dot to signal that
//  auto-retry is active, plus a manual Retry Now button.
//
//  Now automatically listens for connectivity and triggers onRetry 
//  when the device comes back online.
//
//  Drop-in usage (replaces ErrorPage for offline scenarios):
//    if (_isOffline) return OfflineState(onRetry: _loadData);
// ─────────────────────────────────────────────────────────────────────────────

class OfflineState extends StatefulWidget {
  const OfflineState({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  State<OfflineState> createState() => _OfflineStateState();
}

class _OfflineStateState extends State<OfflineState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;
  StreamSubscription<bool>? _connectivitySub;

  static const _amber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );

    // ── Auto-retry when online ──────────────────────────────────────────────
    _connectivitySub = ConnectivityService.instance.onlineStream.listen((online) {
      if (online && mounted) {
        widget.onRetry();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon ──────────────────────────────────────────────────────────
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: _amber.withOpacity(0.07),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _amber.withOpacity(0.22)),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: _amber,
                size: 38,
              ),
            ),
            const SizedBox(height: 24),

            // ── Heading ───────────────────────────────────────────────────────
            const Text(
              "You're Offline",
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),

            // ── Sub-text ──────────────────────────────────────────────────────
            const Text(
              'Check your connection. This page will reload automatically when you reconnect.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textGray,
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 28),

            // ── Pulsing "Listening" indicator ─────────────────────────────────
            FadeTransition(
              opacity: _opacity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: _amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Listening for connection…',
                    style: TextStyle(
                      color: AppColors.textSubtle,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Retry button ──────────────────────────────────────────────────
            SizedBox(
              width: 160,
              height: 44,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ElevatedButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded,
                      size: 16, color: Colors.white),
                  label: const Text(
                    'Retry Now',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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