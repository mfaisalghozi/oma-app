import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../domain/entities/onboarding_step.dart';

final onboardingResumePathProvider = Provider<String>(
  (ref) => Routes.onboardingStep(OnboardingStep.basics.path),
);
