import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/entities/describe_results.dart';
import '../domain/entities/describe_search.dart';
import '../domain/repositories/describe_repository.dart';

class ApiDescribeRepository implements DescribeRepository {
  ApiDescribeRepository(this._client);

  final ApiClient _client;

  @override
  Future<DescribeSearch> create({
    required String query,
    String? retryOf,
    required String idempotencyKey,
  }) async {
    final data = await _client.post(
      '/describe/searches',
      body: {'query': query, 'retry_of': ?retryOf},
      idempotencyKey: idempotencyKey,
    );
    return _search(data);
  }

  @override
  Future<DescribeSearch> status(String searchId) async {
    final data = await _client.get('/describe/searches/$searchId');
    return _search(data);
  }

  @override
  Future<DescribeResults> results(String searchId) async {
    final data = await _client.get('/describe/searches/$searchId/results');
    if (data is! Map) {
      throw const UnexpectedFailure('describe results: unexpected body');
    }
    return DescribeResults.fromJson(data.cast());
  }

  DescribeSearch _search(Object? data) {
    if (data is! Map) {
      throw const UnexpectedFailure('describe: unexpected body');
    }
    return DescribeSearch.fromJson(data.cast());
  }
}
