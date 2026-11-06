abstract interface class OnboardingRepository {
  /// [idempotencyKey] is reused on every retry of one submission.
  Future<void> submit(
    Map<String, Object?> payload, {
    required String idempotencyKey,
  });
}
