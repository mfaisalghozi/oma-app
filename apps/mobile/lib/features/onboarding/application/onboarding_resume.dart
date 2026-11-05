import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../domain/entities/onboarding_step.dart';
import 'onboarding_draft_controller.dart';

/// Null while the draft loads, so the gate waits instead of flashing M06.
final onboardingResumePathProvider = Provider<String?>((ref) {
  final draft = ref.watch(onboardingDraftProvider);
  if (draft.isLoading && !draft.hasValue) return null;
  final step = draft.value?.firstUnfinished ?? OnboardingStep.basics;
  return step == OnboardingStep.setup
      ? Routes.onboardingStep(OnboardingStep.setup.path)
      : Routes.onboardingStep(step.path);
});

String nextStepPath(OnboardingStep step) =>
    Routes.onboardingStep((step.next ?? OnboardingStep.setup).path);
