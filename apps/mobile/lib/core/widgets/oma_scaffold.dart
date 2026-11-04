import 'package:flutter/material.dart';

import '../theme/oma_colors.dart';
import 'oma_back_button.dart';

/// Page frame shared by the auth and onboarding screens: optional back button,
/// optional step counter, title, subtitle, scrollable body and a bottom
/// action area that stays above the keyboard.
class OmaScaffold extends StatelessWidget {
  const OmaScaffold({
    required this.body,
    this.title,
    this.subtitle,
    this.step,
    this.totalSteps = 6,
    this.showBack = true,
    this.onBack,
    this.bottom,
    this.headerTrailing,
    super.key,
  });

  final String? title;
  final String? subtitle;

  /// 1-based onboarding step ("Step 1 of 6"); null hides the counter.
  final int? step;
  final int totalSteps;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget body;

  /// Usually the primary action, pinned to the bottom.
  final Widget? bottom;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showBack || headerTrailing != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    if (showBack) OmaBackButton(onPressed: onBack),
                    const Spacer(),
                    ?headerTrailing,
                  ],
                ),
              ),
            if (step != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: StepCounter(step: step!, total: totalSteps),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      Semantics(
                        header: true,
                        child: Text(
                          title!,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: c.textMuted,
                        ),
                      ),
                    ],
                    if (title != null || subtitle != null)
                      const SizedBox(height: 20),
                    body,
                  ],
                ),
              ),
            ),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }
}

/// "Step 1 of 6" plus the 6 px progress bar from M06 to M11.
class StepCounter extends StatelessWidget {
  const StepCounter({required this.step, required this.total, super.key});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step $step of $total',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Profile setup progress',
          value: '$step of $total',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: step / total,
              minHeight: 6,
              backgroundColor: c.card,
              color: c.primary,
            ),
          ),
        ),
      ],
    );
  }
}
