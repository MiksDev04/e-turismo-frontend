import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app/core/constants/app_colors.dart';

class ToastAnchor {
  const ToastAnchor(this.overlay, this.topInset);

  final OverlayState overlay;
  final double topInset;
}

class AppToast {
  AppToast._();

  static const double _minTopGap = 3.0;
  static const Duration _duration = Duration(seconds: 3);

  static OverlayEntry? _current;
  static GlobalKey<_ToastCardState>? _currentKey;
  static Timer? _timer;
  static String? _currentMessage;

  static ToastAnchor capture(BuildContext context) => ToastAnchor(
        Overlay.of(context, rootOverlay: true),
        MediaQuery.of(context).padding.top,
      );

  static void success(BuildContext c, String m) => successOn(capture(c), m);
  static void warning(BuildContext c, String m) => warningOn(capture(c), m);

  static void successOn(ToastAnchor a, String m) => _show(
        a,
        m,
        AppColors.toastSuccessBg,
        AppColors.toastSuccessFg,
        Icons.check_rounded,
      );

  static void warningOn(ToastAnchor a, String m) => _show(
        a,
        m,
        AppColors.toastWarningBg,
        AppColors.toastWarningFg,
        Icons.priority_high_rounded,
      );

  static void _show(ToastAnchor a, String m, Color bg, Color fg, IconData icon) {
    if (_currentMessage == m) return;
    _dismiss();
    final key = GlobalKey<_ToastCardState>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastCard(
        key: key,
        onDismissed: entry.remove,
        topOffset: a.topInset + _minTopGap,
        message: m,
        bg: bg,
        fg: fg,
        icon: icon,
      ),
    );
    _current = entry;
    _currentKey = key;
    _currentMessage = m;
    a.overlay.insert(entry);
    _timer = Timer(_duration, _dismiss);
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _currentMessage = null;
    final entry = _current;
    final key = _currentKey;
    _current = null;
    _currentKey = null;
    if (entry == null) return;
    final state = key?.currentState;
    if (state == null) {
      entry.remove();
    } else {
      state.dismiss();
    }
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    super.key,
    required this.onDismissed,
    required this.topOffset,
    required this.message,
    required this.bg,
    required this.fg,
    required this.icon,
  });

  final VoidCallback onDismissed;
  final double topOffset;
  final String message;
  final Color bg;
  final Color fg;
  final IconData icon;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  static const double _slideDistance = 16.0;
  static const Duration _enterDuration = Duration(milliseconds: 220);
  static const Duration _exitDuration = Duration(milliseconds: 160);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _enterDuration,
  )..forward();

  bool _exiting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void dismiss() {
    if (_exiting) return;
    _exiting = true;
    _controller.duration = _exitDuration;
    _controller.reverse().whenCompleteOrCancel(widget.onDismissed);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = screenWidth < 520 ? screenWidth - 24.0 : 480.0;
    return Positioned(
      top: widget.topOffset,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_controller.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, -_slideDistance * (1 - t)),
              child: child,
            ),
          );
        },
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: widget.fg.withValues(alpha: 0.25)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: widget.fg, size: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: widget.fg,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
