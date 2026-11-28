import '../entities/describe_results.dart';
import '../entities/describe_search.dart';

abstract interface class DescribeRepository {
  /// 202 on a new search, 200 when the same key replays.
  Future<DescribeSearch> create({
    required String query,
    String? retryOf,
    required String idempotencyKey,
  });

  Future<DescribeSearch> status(String searchId);

  Future<DescribeResults> results(String searchId);
}
