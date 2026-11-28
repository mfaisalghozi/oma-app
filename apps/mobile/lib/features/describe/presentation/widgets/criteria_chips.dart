import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../data/criterion_label.dart';
import '../../domain/entities/describe_criteria.dart';

/// Must (filled), Nice (outlined), Not searchable (greyed, with the info icon
/// that says OMA cannot search this).
class CriteriaChips extends StatelessWidget {
  const CriteriaChips({
    required this.criteria,
    this.compact = false,
    super.key,
  });

  final DescribeCriteria criteria;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final groups = <(String, List<Widget>)>[
      if (criteria.must.isNotEmpty)
        (
          'Must have',
          [
            for (final item in criteria.must)
              _Chip(
                label: CriterionLabel.of(item),
                filled: true,
                colour: c.primary,
                onColour: c.onPrimary,
              ),
          ],
        ),
      if (criteria.nice.isNotEmpty)
        (
          'Nice to have',
          [
            for (final item in criteria.nice)
              _Chip(
                label: CriterionLabel.of(item),
                filled: false,
                colour: c.text,
                onColour: c.text,
              ),
          ],
        ),
      if (criteria.notSearchable.isNotEmpty)
        (
          'Not searchable',
          [
            for (final item in criteria.notSearchable)
              _Chip(
                label: CriterionLabel.notSearchable(item),
                filled: false,
                colour: c.textMuted,
                onColour: c.textMuted,
                icon: Icons.info_outline_rounded,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("OMA can't search this"),
                    content: Text(
                      '"${item.text}" is not a profile field, so it is ignored '
                      'when matching.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
    ];
    if (groups.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, chips) in groups) ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
          if (!compact) const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.filled,
    required this.colour,
    required this.onColour,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool filled;
  final Color colour;
  final Color onColour;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: filled ? colour : c.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: filled ? colour : c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: onColour),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: filled ? onColour : colour,
            ),
          ),
        ],
      ),
    );
    return onTap == null ? body : GestureDetector(onTap: onTap, child: body);
  }
}
