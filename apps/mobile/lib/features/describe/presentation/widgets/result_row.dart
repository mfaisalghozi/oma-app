import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../data/criterion_label.dart';
import '../../domain/entities/describe_result.dart';

/// One match. Photo first (initial as fallback), name and age, distance, the
/// server's reason, and the N of M pill. A stale profile hides the reason line
/// and the pill and says so instead.
class ResultRow extends StatelessWidget {
  const ResultRow({required this.row, super.key});

  final DescribeResultRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final card = row.candidate;
    final close = CriterionLabel.closeReason(row);
    final matched = row.matched;
    final total = row.total;
    final complete = matched != null && total != null && matched >= total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: c.mint,
            foregroundImage: card.photos.isEmpty
                ? null
                : NetworkImage(card.photos.first.readUrl),
            child: Text(
              card.displayName.isEmpty ? '?' : card.displayName.substring(0, 1),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: c.primaryStrong,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${card.displayName}, ${card.age}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                        ),
                      ),
                    ),
                    Text(
                      '${card.approxDistanceKm} km',
                      style: TextStyle(fontSize: 13, color: c.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (row.profileUpdated)
                  Text(
                    'Profile updated since your search',
                    style: TextStyle(fontSize: 13, color: c.textMuted),
                  )
                else ...[
                  if (row.reason case final reason?)
                    Text(
                      reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.textMuted),
                    ),
                  if (close != null)
                    Text(
                      close,
                      style: TextStyle(fontSize: 13, color: c.accent),
                    ),
                  if (matched != null && total != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: complete ? c.mint : c.background,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: complete ? c.mint : c.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (complete) ...[
                            Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: c.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            'Matches $matched of $total',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: complete ? c.primaryStrong : c.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
