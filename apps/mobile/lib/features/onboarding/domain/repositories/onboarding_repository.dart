abstract interface class OnboardingRepository {
  /// `POST /v1/me/onboarding`. [idempotencyKey] is the same on every retry
  /// of one submission, so a retry never creates a second profile.
  Future<void> submit(
    Map<String, Object?> payload, {
    required String idempotencyKey,
  });
}
