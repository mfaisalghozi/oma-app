import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../domain/entities/swipe_kind.dart';

/// The word that fades in as the card leaves the stack.
class SwipeStamp extends StatelessWidget {
  const SwipeStamp({required this.kind, required this.opacity, super.key});

  final SwipeKind kind;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final (label, colour, angle) = switch (kind) {
      SwipeKind.like => ('LIKE', c.primary, -0.20),
      SwipeKind.pass => ('PASS', c.textMuted, 0.20),
      SwipeKind.superLike => ('SUPER LIKE', c.accent, 0.0),
    };
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0, 1),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: colour, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: colour,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
