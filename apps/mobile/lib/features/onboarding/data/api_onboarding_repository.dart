import '../../../core/api/api_client.dart';
import '../domain/repositories/onboarding_repository.dart';

class ApiOnboardingRepository implements OnboardingRepository {
  ApiOnboardingRepository(this._api);

  final ApiClient _api;

  @override
  Future<void> submit(
    Map<String, Object?> payload, {
    required String idempotencyKey,
  }) => _api.post(
    '/me/onboarding',
    body: payload,
    idempotencyKey: idempotencyKey,
  );
}
