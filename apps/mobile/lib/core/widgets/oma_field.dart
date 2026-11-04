import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/oma_colors.dart';

/// Labelled 52 px text field with an optional hint line under it.
class OmaField extends StatelessWidget {
  const OmaField({
    required this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.placeholder,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.maxLength,
    this.maxLines = 1,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.readOnly = false,
    this.onTap,
    this.showCounter = false,
    this.inputFormatters,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? errorText;
  final String? placeholder;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final int? maxLength;
  final int maxLines;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final bool readOnly;
  final VoidCallback? onTap;

  /// Shows "82/255" under the field (bio, ambition).
  final bool showCounter;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
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
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          maxLength: maxLength,
          maxLines: maxLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          autofillHints: autofillHints,
          readOnly: readOnly,
          onTap: onTap,
          inputFormatters: inputFormatters,
          style: TextStyle(fontSize: 16, color: c.text),
          decoration: InputDecoration(
            hintText: placeholder,
            errorText: errorText,
            helperText: errorText == null ? hint : null,
            helperMaxLines: 3,
            errorMaxLines: 3,
            suffixIcon: suffix,
            counterText: showCounter ? null : '',
            semanticCounterText: showCounter ? null : '',
          ),
        ),
      ],
    );
  }
}
