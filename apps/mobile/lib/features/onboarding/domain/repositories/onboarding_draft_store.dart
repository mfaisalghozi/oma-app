import '../entities/onboarding_draft.dart';

/// Where the draft lives between app launches.
abstract interface class OnboardingDraftStore {
  Future<OnboardingDraft?> load();
  Future<void> save(OnboardingDraft draft);
  Future<void> clear();
}
