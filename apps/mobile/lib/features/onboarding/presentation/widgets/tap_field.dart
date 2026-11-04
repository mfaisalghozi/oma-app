import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';

/// Field-looking button for values picked from a sheet or date picker
/// (Birthdate, Education, Religion, Personality). Same look as `OmaField`.
class TapField extends StatelessWidget {
  const TapField({
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'Choose',
    this.hint,
    this.errorText,
    this.icon = Icons.expand_more,
    super.key,
  });

  final String label;
  final String? value;
  final String placeholder;
  final String? hint;
  final String? errorText;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final empty = value == null || value!.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: label,
          value: value,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              isEmpty: empty,
              decoration: InputDecoration(
                hintText: placeholder,
                helperText: errorText == null ? hint : null,
                helperMaxLines: 2,
                errorText: errorText,
                errorMaxLines: 2,
                suffixIcon: Icon(icon, color: c.textMuted),
              ),
              child: Text(
                empty ? '' : value!,
                style: TextStyle(fontSize: 16, color: c.text),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
