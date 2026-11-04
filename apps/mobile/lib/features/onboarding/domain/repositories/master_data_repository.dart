import '../entities/master_option.dart';

abstract interface class MasterDataRepository {
  /// One page of [type], optionally filtered by [query] or [categoryId].
  Future<MasterDataPage> page(
    MasterDataType type, {
    String? query,
    String? categoryId,
    int page = 1,
    int limit = 20,
  });
}
