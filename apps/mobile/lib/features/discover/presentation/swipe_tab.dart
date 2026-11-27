import 'package:flutter/material.dart';

import '../../../core/theme/oma_colors.dart';

/// The deck frame. DSC-FE-02 replaces the skeleton with the card stack.
class SwipeTab extends StatelessWidget {
  const SwipeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style_outlined,
              size: 40,
              color: c.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            _Bar(width: 148, colour: c.border),
            const SizedBox(height: 10),
            _Bar(width: 96, colour: c.border),
            const SizedBox(height: 10),
            _Bar(width: 120, colour: c.border),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.colour});

  final double width;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
