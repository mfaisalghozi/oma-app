import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/api_master_data_repository.dart';
import '../domain/entities/master_option.dart';
import '../domain/repositories/master_data_repository.dart';

final masterDataRepositoryProvider = Provider<MasterDataRepository>(
  (ref) => ApiMasterDataRepository(ref.watch(apiClientProvider)),
);

/// Not auto-disposed: loads once per app session; `ref.invalidate` retries.
final masterOptionsProvider =
    FutureProvider.family<List<MasterOption>, MasterDataType>((
      ref,
      type,
    ) async {
      final repo = ref.watch(masterDataRepositoryProvider);
      final items = <MasterOption>[];
      var page = 1;
      while (true) {
        final p = await repo.page(type, page: page, limit: 100);
        items.addAll(p.items);
        if (!p.hasMore || page >= 10) break;
        page++;
      }
      return items;
    }, retry: (_, _) => null);

final hobbiesByCategoryProvider = FutureProvider.family<MasterDataPage, String>(
  (ref, categoryId) => ref
      .watch(masterDataRepositoryProvider)
      .page(MasterDataType.hobby, categoryId: categoryId),
  retry: (_, _) => null,
);

class PickedLabels extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void remember(Iterable<MasterOption> options) {
    state = {...state, for (final o in options) o.id: o.label};
  }
}

final pickedLabelsProvider =
    NotifierProvider<PickedLabels, Map<String, String>>(PickedLabels.new);
