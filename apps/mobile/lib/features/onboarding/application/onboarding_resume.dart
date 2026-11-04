import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../domain/entities/onboarding_step.dart';
import 'onboarding_draft_controller.dart';

/// Where the gates send a user whose onboarding is incomplete: the first
/// unfinished step of the local draft.
///
/// Null while the draft is still loading, so the gate waits on the splash
/// instead of flashing M06 before jumping ahead. A draft that fails to load
/// falls back to the first step.
final onboardingResumePathProvider = Provider<String?>((ref) {
  final draft = ref.watch(onboardingDraftProvider);
  if (draft.isLoading && !draft.hasValue) return null;
  final step = draft.value?.firstUnfinished ?? OnboardingStep.basics;
  return step == OnboardingStep.setup
      ? Routes.onboardingStep(OnboardingStep.setup.path)
      : Routes.onboardingStep(step.path);
});

/// Path of the step after [step], for each screen's Next button.
String nextStepPath(OnboardingStep step) =>
    Routes.onboardingStep((step.next ?? OnboardingStep.setup).path);
