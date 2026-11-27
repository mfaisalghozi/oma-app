import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';
import '../discover_mode.dart';

class ModeSwitch extends StatelessWidget {
  const ModeSwitch({
    required this.mode,
    required this.onChanged,
    this.showDescribe = true,
    super.key,
  });

  final DiscoverMode mode;
  final ValueChanged<DiscoverMode> onChanged;
  final bool showDescribe;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    if (!showDescribe) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          _Segment(
            label: 'Swipe',
            icon: Icons.style_outlined,
            selected: mode == DiscoverMode.swipe,
            onTap: () => onChanged(DiscoverMode.swipe),
          ),
          _Segment(
            label: 'Describe',
            icon: Icons.auto_awesome_outlined,
            selected: mode == DiscoverMode.describe,
            onTap: () => onChanged(DiscoverMode.describe),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final fg = selected ? c.primary : c.textMuted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? c.background : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
