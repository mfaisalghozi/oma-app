import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/entities/daily_usage.dart';
import '../domain/repositories/usage_repository.dart';

class ApiUsageRepository implements UsageRepository {
  ApiUsageRepository(this._api);

  final ApiClient _api;

  @override
  Future<DailyUsage> fetch() async {
    final data = await _api.get('/me/usage');
    if (data is! Map) {
      throw const UnexpectedFailure('me/usage: unexpected body');
    }
    return DailyUsage.fromJson(data.cast());
  }
}
