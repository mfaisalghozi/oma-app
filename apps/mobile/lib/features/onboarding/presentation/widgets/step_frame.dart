import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/widgets/oma_button.dart';
import '../../../../core/widgets/oma_scaffold.dart';
import '../../application/onboarding_draft_controller.dart';
import '../../application/onboarding_resume.dart';
import '../../domain/entities/onboarding_step.dart';

class StepFrame extends ConsumerWidget {
  const StepFrame({
    required this.step,
    required this.title,
    required this.body,
    required this.canContinue,
    this.subtitle,
    this.nextLabel = 'Next',
    this.onNext,
    this.footer,
    super.key,
  });

  final OnboardingStep step;
  final String title;
  final String? subtitle;
  final Widget body;
  final bool canContinue;
  final String nextLabel;

  final Future<void> Function()? onNext;

  final Widget? footer;

  static OnboardingStep? previous(OnboardingStep step) =>
      step.index == 0 ? null : OnboardingStep.values[step.index - 1];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prev = previous(step);
    final draft = ref.read(onboardingDraftProvider.notifier);
    return OmaScaffold(
      step: step.number,
      title: title,
      subtitle: subtitle,
      showBack: prev != null,
      onBack: prev == null
          ? null
          : () async {
              await draft.flush();
              if (context.mounted) {
                context.go(Routes.onboardingStep(prev.path));
              }
            },
      body: body,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OmaButton(
            label: nextLabel,
            onPressed: canContinue
                ? () async {
                    if (onNext != null) return onNext!();
                    await draft.flush();
                    if (context.mounted) context.go(nextStepPath(step));
                  }
                : null,
          ),
          ?footer,
        ],
      ),
    );
  }
}

class StepLabel extends StatelessWidget {
  const StepLabel(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleSmall),
        ),
        ?trailing,
      ],
    ),
  );
}
