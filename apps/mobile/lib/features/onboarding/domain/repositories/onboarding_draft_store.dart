import '../entities/onboarding_draft.dart';

abstract interface class OnboardingDraftStore {
  Future<OnboardingDraft?> load();
  Future<void> save(OnboardingDraft draft);
  Future<void> clear();
}
