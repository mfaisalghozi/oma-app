import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/entities/master_option.dart';
import '../domain/repositories/master_data_repository.dart';

class ApiMasterDataRepository implements MasterDataRepository {
  ApiMasterDataRepository(this._api);

  final ApiClient _api;

  @override
  Future<MasterDataPage> page(
    MasterDataType type, {
    String? query,
    String? categoryId,
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _api.get(
      '/master-data',
      query: {
        'type': type.wire,
        if (query != null && query.isNotEmpty) 'q': query,
        'category_id': ?categoryId,
        'page': page,
        'limit': limit,
      },
    );
    if (data is! Map) {
      throw const UnexpectedFailure('master-data: unexpected body');
    }
    final items = [
      for (final i in (data['items'] as List?) ?? const [])
        if (i is Map) MasterOption.fromJson(i.cast()),
    ];
    final p = data['pagination'];
    // Small lists (gender, religion, …) come without pagination.
    return MasterDataPage(
      items: items,
      page: p is Map ? (p['page'] as num? ?? page).toInt() : 1,
      totalPages: p is Map ? (p['total_pages'] as num? ?? 1).toInt() : 1,
    );
  }
}
