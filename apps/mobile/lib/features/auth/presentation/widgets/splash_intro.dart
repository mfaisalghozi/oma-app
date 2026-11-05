import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../../../core/widgets/brand.dart';

/// Capped at [duration]; the gates cut it short once the session resolves.
class SplashIntro extends StatefulWidget {
  const SplashIntro({
    this.duration = const Duration(milliseconds: 1500),
    super.key,
  });

  final Duration duration;

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

class _SplashIntroState extends State<SplashIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  // Timings from the board (ms), scaled into the 1.5 s cap.
  static const _boardTotal = 1960.0;

  Animation<double> _interval(double startMs, double lengthMs, Curve curve) {
    final begin = (startMs / _boardTotal).clamp(0.0, 1.0);
    final end = ((startMs + lengthMs) / _boardTotal).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _c,
      curve: Interval(begin, end, curve: curve),
    );
  }

  late final _icon = _interval(80, 620, Curves.linear);
  late final _ring = _interval(560, 800, Curves.easeOut);
  late final _tag = _interval(700, 400, Curves.easeOut);
  late final _bubbles = [
    for (final delay in [500.0, 620.0, 740.0, 860.0])
      _interval(delay, 1100, Curves.easeOut),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Overshoot curve matching cubic-bezier(0.34, 1.56, 0.64, 1): 0.6 → 1.06 → 1.
  static double _pop(double t) {
    if (t < 0.6) return 0.6 + (1.06 - 0.6) * Curves.easeOut.transform(t / 0.6);
    return 1.06 - 0.06 * Curves.easeInOut.transform((t - 0.6) / 0.4);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final iconT = _icon.value;
        final iconOpacity = (iconT / 0.6).clamp(0.0, 1.0);
        final iconDy = iconT < 0.6
            ? 24 - 30 * (iconT / 0.6)
            : -6 + 6 * ((iconT - 0.6) / 0.4);
        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: 160,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  for (var i = 0; i < _bubbles.length; i++)
                    _Bubble(
                      t: _bubbles[i].value,
                      size: const [10.0, 8.0, 12.0, 6.0][i],
                      dx: const [-20.0, 14.0, -4.0, 24.0][i],
                      color: c.primary,
                    ),
                  Opacity(
                    opacity: _ring.value == 0 ? 0 : 0.5 * (1 - _ring.value),
                    child: Transform.scale(
                      scale: 0.9 + _ring.value,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: c.primary, width: 3),
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: iconOpacity,
                    child: Transform.translate(
                      offset: Offset(0, iconDy),
                      child: Transform.scale(
                        scale: _pop(iconT),
                        child: const OmaAppIcon(size: 160),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: Opacity(
                opacity: _tag.value,
                child: Transform.translate(
                  offset: Offset(0, 8 * (1 - _tag.value)),
                  child: Text(
                    'Ocean Match',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.56,
                      color: c.primaryStrong,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.t,
    required this.size,
    required this.dx,
    required this.color,
  });

  final double t;
  final double size;
  final double dx;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (t == 0 || t == 1) return const SizedBox.shrink();
    final opacity = t < 0.2 ? t / 0.2 * 0.9 : 0.9 * (1 - (t - 0.2) / 0.8);
    return Positioned(
      top: 18,
      child: Transform.translate(
        offset: Offset(dx * t, -170 * t),
        child: Transform.scale(
          scale: 0.4 + 0.6 * t,
          child: Opacity(
            opacity: math.max(0, opacity),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.7),
                border: Border.all(color: color, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
