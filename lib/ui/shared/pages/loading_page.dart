import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class LoadingPage extends StatefulWidget {
  const LoadingPage({
    super.key,
    this.message = 'Loading, please wait…',
  });

  final String message;

  @override
  State<LoadingPage> createState() => _LoadingPageState();
}

class _LoadingPageState extends State<LoadingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Emoji ────────────────────────────────────────────────────────
          const Text('🏨', style: TextStyle(fontSize: 38)),
          const SizedBox(height: 24),

          // ── Progress bar + message ────────────────────────────────────────
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    height: 5,
                    width: double.infinity,
                    color: AppColors.cardBorder,
                    child: AnimatedBuilder(
                      animation: _shimmer,
                      builder: (_, __) {
                        return FractionallySizedBox(
                          widthFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                stops: const [0.0, 0.4, 0.6, 1.0],
                                colors: [
                                  AppColors.cardBorder,
                                  AppColors.gradientStart,
                                  AppColors.gradientEnd,
                                  AppColors.cardBorder,
                                ],
                                transform: _SlideTransform(_shimmer.value),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Message ─────────────────────────────────────────────────
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Shifts the gradient horizontally using a GradientTransform
class _SlideTransform extends GradientTransform {
  const _SlideTransform(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * t, 0, 0);
  }
}