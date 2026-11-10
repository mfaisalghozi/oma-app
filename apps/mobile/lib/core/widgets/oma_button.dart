import 'package:flutter/material.dart';

import '../theme/oma_colors.dart';

enum OmaButtonVariant { primary, secondary, text }

class OmaButton extends StatelessWidget {
  const OmaButton({
    required this.label,
    required this.onPressed,
    this.onDisabledTap,
    this.variant = OmaButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    super.key,
  });

  const OmaButton.secondary({
    required this.label,
    required this.onPressed,
    this.onDisabledTap,
    this.icon,
    this.loading = false,
    this.expand = true,
    super.key,
  }) : variant = OmaButtonVariant.secondary;

  const OmaButton.text({
    required this.label,
    required this.onPressed,
    this.onDisabledTap,
    this.icon,
    this.loading = false,
    this.expand = true,
    super.key,
  }) : variant = OmaButtonVariant.text;

  final String label;

  final VoidCallback? onPressed;

  /// Fires on a tap while the button is disabled. Lets a blocked form say why.
  final VoidCallback? onDisabledTap;
  final OmaButtonVariant variant;
  final Widget? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final enabled = onPressed != null && !loading;
    final (bg, fg, side) = switch (variant) {
      OmaButtonVariant.primary => (
        enabled ? c.primary : c.card,
        enabled ? c.onPrimary : c.textMuted,
        BorderSide.none,
      ),
      OmaButtonVariant.secondary => (
        c.background,
        enabled ? c.text : c.textMuted,
        BorderSide(color: c.border),
      ),
      OmaButtonVariant.text => (
        Colors.transparent,
        enabled ? c.primary : c.textMuted,
        BorderSide.none,
      ),
    };

    final child = loading
        ? SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[icon!, const SizedBox(width: 8)],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );

    final button = TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg,
        disabledForegroundColor: fg,
        shape: StadiumBorder(side: side),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: child,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? label : null,
      child: SizedBox(
        width: expand ? double.infinity : null,
        height: 52,
        child: !enabled && onDisabledTap != null
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDisabledTap,
                child: button,
              )
            : button,
      ),
    );
  }
}
