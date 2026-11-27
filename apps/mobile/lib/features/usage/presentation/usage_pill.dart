import 'package:flutter/material.dart';

import '../../../core/theme/oma_colors.dart';
import '../domain/entities/daily_usage.dart';

enum UsagePillKind { likes, searches }

/// `12 of 15 likes left today`, or the reset time once the balance is spent.
class UsagePill extends StatelessWidget {
  const UsagePill({required this.usage, required this.kind, super.key});

  final DailyUsage usage;
  final UsagePillKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final balance = kind == UsagePillKind.likes ? usage.likes : usage.searches;
    final noun = kind == UsagePillKind.likes ? 'likes' : 'searches';
    final label = balance.isExhausted
        ? '${balance.available} of ${balance.limit} $noun left · resets ${_clock(usage.resetsAt)}'
        : '${balance.available} of ${balance.limit} $noun left today';
    final fg = balance.isExhausted ? c.error : c.primaryStrong;
    final bg = balance.isExhausted ? c.errorSurface : c.mint;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              kind == UsagePillKind.likes
                  ? Icons.favorite_rounded
                  : Icons.search_rounded,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(DateTime when) {
    final local = when.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
