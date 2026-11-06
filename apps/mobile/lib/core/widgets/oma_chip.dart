import 'package:flutter/material.dart';

import '../theme/oma_colors.dart';

class OmaChoiceChip extends StatelessWidget {
  const OmaChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.primary : c.background,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? c.primary : c.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: 18, color: c.onPrimary),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected ? c.onPrimary : c.text,
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
