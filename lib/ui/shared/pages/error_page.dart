import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';

// ─── Error Page ───────────────────────────────────────────────────────────────
//
// Usage examples:
//
//   ErrorPage(statusCode: 503, onRetry: _loadData)  // No internet
//   ErrorPage(statusCode: 404, onRetry: _loadData)  // Not found
//   ErrorPage(statusCode: 401)                       // Unauthorized (no retry)
//   ErrorPage(statusCode: 500, onRetry: _loadData)  // Server error

class ErrorPage extends StatelessWidget {
  const ErrorPage({
    super.key,
    required this.statusCode,
    this.onRetry,
  });

  final int statusCode;

  /// If null, the retry button is hidden.
  final VoidCallback? onRetry;

  // ── Config per status code ────────────────────────────────────────────────

  _ErrorConfig get _config {
    switch (statusCode) {
      case 0:
      case 503:
        return const _ErrorConfig(
          icon: Icons.wifi_off_rounded,
          label: 'No Internet Connection',
          message: 'Please check your connection and try again.',
          color: Color(0xFFF59E0B),
        );
      case 401:
        return const _ErrorConfig(
          icon: Icons.lock_outline_rounded,
          label: 'Session Expired',
          message: 'Please log in again to continue.',
          color: Color(0xFFEF4444),
        );
      case 403:
        return const _ErrorConfig(
          icon: Icons.block_rounded,
          label: 'Access Restricted',
          message: "You don't have permission to view this page.",
          color: Color(0xFFEF4444),
        );
      case 404:
        return const _ErrorConfig(
          icon: Icons.search_off_rounded,
          label: 'Nothing Here',
          message: "The data you're looking for could not be found.",
          color: AppColors.primaryCyan,
        );
      case 408:
        return const _ErrorConfig(
          icon: Icons.timer_off_rounded,
          label: 'Taking Too Long',
          message: 'The server is taking too long to respond. Please try again.',
          color: Color(0xFFF59E0B),
        );
      case 500:
        return const _ErrorConfig(
          icon: Icons.cloud_off_rounded,
          label: 'Server Unavailable',
          message: 'Our servers are having trouble. Please try again shortly.',
          color: Color(0xFFEF4444),
        );
      default:
        return const _ErrorConfig(
          icon: Icons.error_outline_rounded,
          label: 'Something Went Wrong',
          message: 'An unexpected error occurred. Please try again.',
          color: AppColors.textGray,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _config;

    return SizedBox(
      width: double.infinity,
      height: MediaQuery.of(context).size.height * 0.7,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ──────────────────────────────────────────────────────
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: cfg.color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cfg.color.withOpacity(0.25)),
                ),
                child: Icon(cfg.icon, color: cfg.color, size: 40),
              ),
              const SizedBox(height: 24),

              // ── Status code ───────────────────────────────────────────────
              Text(
                '$statusCode',
                style: TextStyle(
                  color: cfg.color.withOpacity(0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),

              // ── Label ─────────────────────────────────────────────────────
              Text(
                cfg.label,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // ── Message ───────────────────────────────────────────────────
              Text(
                cfg.message,
                style: const TextStyle(
                  color: AppColors.textGray,
                  fontSize: 13.5,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),

              // ── Retry button ──────────────────────────────────────────────
              if (onRetry != null) ...[
                const SizedBox(height: 32),
                SizedBox(
                  width: 160,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cfg.color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
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

// ─── Internal config model ────────────────────────────────────────────────────

class _ErrorConfig {
  const _ErrorConfig({
    required this.icon,
    required this.label,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String message;
  final Color color;
}