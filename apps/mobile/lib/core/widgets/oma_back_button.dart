import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/oma_colors.dart';

class OmaBackButton extends StatelessWidget {
  const OmaBackButton({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: 'Back',
        onPressed:
            onPressed ??
            () =>
                context.canPop() ? context.pop() : Navigator.maybePop(context),
        style: IconButton.styleFrom(
          backgroundColor: c.background,
          foregroundColor: c.text,
          shape: CircleBorder(side: BorderSide(color: c.border)),
        ),
        icon: const Icon(Icons.arrow_back_rounded, size: 22),
      ),
    );
  }
}
