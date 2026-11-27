import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../../../core/widgets/brand.dart';
import 'super_like_chip.dart';

/// Wordmark and subtitle on the left. The super-like balance chip is built but
/// stays hidden: no endpoint returns the balance this sprint (SA section 16).
class DiscoverHeader extends StatelessWidget {
  const DiscoverHeader({this.showSuperLikeChip = false, super.key});

  /// Flip to true when the BE exposes a balance read. The chip is already
  /// built so the board layout does not change when it lands.
  final bool showSuperLikeChip;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'OMA',
                image: true,
                child: Image.asset(BrandAssets.wordmark, height: 30),
              ),
              const SizedBox(height: 2),
              Text(
                'Ocean Match',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (showSuperLikeChip) const SuperLikeChip(balance: 0),
      ],
    );
  }
}
