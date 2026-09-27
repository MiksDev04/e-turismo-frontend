import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';
import 'package:app/router/app_router.dart';
import 'package:app/core/services/offline_service.dart';
import 'package:app/core/services/session_service.dart';
import 'package:app/core/widgets/app_toast.dart';
import 'dart:async';

// ─── App ──────────────────────────────────────────────────────────────────────

class App extends StatelessWidget {
  const App({super.key});

  // The sync listener lives in MaterialApp.builder, which is a *sibling* of
  // the Navigator — there is no Overlay above it for AppToast to find. This
  // key is how the sync banner reaches the root overlay.
  static final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SessionService.instance,
      builder: (context, child) {
        return MaterialApp(
          title: _getDynamicTitle(),
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,

          // ── Theme ──────────────────────────────────────────────────────────────
          theme: _buildTheme(),

          // ── Routing ────────────────────────────────────────────────────────────
          initialRoute: '/',
          onGenerateRoute: AppRouter.onGenerateRoute,
          builder: (context, child) {
            return Column(
              children: [
                Expanded(child: child ?? const SizedBox.shrink()),
                const SyncBannerOverlay(),
              ],
            );
          },
        );
      },
    );
  }

  static String _getDynamicTitle() {
    final session = SessionService.instance.current;
    if (session == null) return 'San Pablo Tourism';
    if (session.role == 'admin') return 'San Pablo Tourism Admin';
    if (session.role == 'business') return 'San Pablo Tourism Business';
    return 'San Pablo Tourism';
  }

  static ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      colorScheme: ColorScheme.dark(
        surface: AppColors.backgroundDark,
        primary: AppColors.primaryCyan,
        secondary: AppColors.primaryBlue,
        error: AppColors.accentRed,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: AppColors.textWhite),
        bodySmall: TextStyle(color: AppColors.textGray),
      ),
      dividerColor: AppColors.cardBorder,
    );
  }
}

// ─── Sync Banner ──────────────────────────────────────────────────────────────

class SyncBannerOverlay extends StatefulWidget {
  const SyncBannerOverlay({super.key});

  @override
  State<SyncBannerOverlay> createState() => _SyncBannerOverlayState();
}

class _SyncBannerOverlayState extends State<SyncBannerOverlay> {
  // True while a sync cycle is user-visible, i.e. one that had records
  // actually waiting to push. An idle poll on a clean account emits
  // syncing → synced with pendingCount 0 and must stay silent.
  bool _cycleActive = false;
  StreamSubscription<SyncState>? _subscription;

  @override
  void initState() {
    super.initState();

    // Listen to the stream here — NOT inside build — so a state that was
    // already active before this widget mounted is not missed.
    _subscription = SyncService.instance.syncStateStream.listen(_onSyncState);

    // Handle a state that was already active before this widget mounted.
    final initial = SyncService.instance.currentState;
    if (initial.status != SyncStatus.idle) {
      _onSyncState(initial);
    }
  }

  void _onSyncState(SyncState state) {
    switch (state.status) {
      case SyncStatus.syncing:
        // Only surface the cycle if there are actually local items pending.
        _cycleActive = state.pendingCount > 0;
        if (_cycleActive) {
          _toast(AppToast.warningOn, 'Syncing offline data…');
        }
        break;

      case SyncStatus.error:
        // If we were already syncing something (pushed something) or there
        // are still items pending.
        if (_cycleActive || state.pendingCount > 0) {
          _cycleActive = true;
          final message = state.errorMessage ?? 'Sync failed.';
          _toast(
            AppToast.warningOn,
            message.length > 60 ? '${message.substring(0, 59)}…' : message,
          );
        }
        break;

      case SyncStatus.synced:
        // Only confirm if we were actually showing a cycle.
        if (_cycleActive) {
          _cycleActive = false;
          _toast(AppToast.successOn, 'Data synced.');
        }
        break;

      case SyncStatus.idle:
        _cycleActive = false;
        break;
    }
  }

  void _toast(void Function(ToastAnchor, String) show, String message) {
    // Null before the Navigator has mounted — e.g. the currentState re-read
    // in initState landing ahead of the first frame. The cycle flag is
    // already set, so the follow-up state still reports itself.
    final overlay = App._navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    show(ToastAnchor(overlay, MediaQuery.of(context).padding.top), message);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  // This widget exists only to hold the stream subscription and provide a
  // context for AppToast.capture. The toast itself renders in the root
  // overlay via navigatorKey, so there is nothing to build here.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
