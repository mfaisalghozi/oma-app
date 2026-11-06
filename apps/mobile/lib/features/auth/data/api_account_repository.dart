import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/entities/account_state.dart';
import '../domain/repositories/account_repository.dart';

class ApiAccountRepository implements AccountRepository {
  ApiAccountRepository(this._api);

  final ApiClient _api;

  @override
  Future<AccountState> initialize() async {
    final data = await _api.post('/me/initialize');
    if (data is! Map) {
      throw const UnexpectedFailure('initialize: unexpected body');
    }
    return AccountState.fromJson(data.cast<String, Object?>());
  }
}
