import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../domain/entities/onboarding_step.dart';

/// Where the gates send a user whose onboarding is incomplete.
///
/// Starts at the first step; ONB-FE-06 replaces this with the first
/// unfinished step from the local OnboardingDraft.
final onboardingResumePathProvider = Provider<String>(
  (ref) => Routes.onboardingStep(OnboardingStep.basics.path),
);
