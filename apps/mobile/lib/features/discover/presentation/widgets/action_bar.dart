import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../domain/entities/swipe_kind.dart';

/// Pass, Comment, Super like, Like. The Like button is the filled one.
class ActionBar extends StatelessWidget {
  const ActionBar({
    required this.onAction,
    required this.onComment,
    this.enabled = true,
    super.key,
  });

  final ValueChanged<SwipeKind> onAction;
  final VoidCallback onComment;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundAction(
          icon: Icons.close_rounded,
          label: 'Pass',
          colour: c.text,
          border: c.border,
          background: c.background,
          onPressed: enabled ? () => onAction(SwipeKind.pass) : null,
        ),
        const SizedBox(width: 18),
        _RoundAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Comment',
          colour: c.textMuted,
          border: c.border,
          background: c.background,
          onPressed: enabled ? onComment : null,
        ),
        const SizedBox(width: 18),
        _RoundAction(
          icon: Icons.star_rounded,
          label: 'Super like',
          colour: c.accent,
          border: c.accent,
          background: c.background,
          onPressed: enabled ? () => onAction(SwipeKind.superLike) : null,
        ),
        const SizedBox(width: 18),
        _RoundAction(
          icon: Icons.favorite_rounded,
          label: 'Like',
          colour: c.onPrimary,
          border: c.primary,
          background: c.primary,
          size: 64,
          onPressed: enabled ? () => onAction(SwipeKind.like) : null,
        ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.colour,
    required this.border,
    required this.background,
    required this.onPressed,
    this.size = 56,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final Color border;
  final Color background;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: background,
          shape: CircleBorder(side: BorderSide(color: border, width: 1.5)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Icon(
              icon,
              size: size * 0.42,
              color: onPressed == null ? colour.withValues(alpha: 0.4) : colour,
            ),
          ),
        ),
      ),
    );
  }
}
