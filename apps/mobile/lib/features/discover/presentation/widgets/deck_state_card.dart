import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../../../core/widgets/oma_button.dart';

/// One frame for Out of likes, Out of fish, Offline and Error. Same card shape
/// as the board, so the deck area never jumps.
class DeckStateCard extends StatelessWidget {
  const DeckStateCard({
    required this.icon,
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.nudge,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Widget? nudge;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: c.primaryStrong),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.45, color: c.textMuted),
          ),
          if (nudge case final nudge?) ...[const SizedBox(height: 20), nudge],
          if (primaryLabel case final label?) ...[
            const SizedBox(height: 24),
            OmaButton(label: label, onPressed: onPrimary),
          ],
          if (secondaryLabel case final label?) ...[
            const SizedBox(height: 10),
            OmaButton(
              label: label,
              onPressed: onSecondary,
              variant: OmaButtonVariant.secondary,
            ),
          ],
        ],
      ),
    );
  }
}
