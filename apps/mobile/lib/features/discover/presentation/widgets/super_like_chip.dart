import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';

/// Super-like balance chip. Built for the board layout, but hidden until the BE
/// exposes a balance read: most accounts get SUPER_LIKE_BALANCE_EMPTY and no
/// endpoint returns the number (SA section 16).
class SuperLikeChip extends StatelessWidget {
  const SuperLikeChip({required this.balance, super.key});

  final int balance;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Semantics(
      label: '$balance super likes',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 18, color: c.accent),
            const SizedBox(width: 6),
            Text(
              '$balance',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: c.primaryStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
