import '../entities/master_option.dart';

abstract interface class MasterDataRepository {
  Future<MasterDataPage> page(
    MasterDataType type, {
    String? query,
    String? categoryId,
    int page = 1,
    int limit = 20,
  });
}
