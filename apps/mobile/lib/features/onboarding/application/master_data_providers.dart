import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/api_master_data_repository.dart';
import '../domain/entities/master_option.dart';
import '../domain/repositories/master_data_repository.dart';

final masterDataRepositoryProvider = Provider<MasterDataRepository>(
  (ref) => ApiMasterDataRepository(ref.watch(apiClientProvider)),
);

/// Every option of a short list (gender, show_me, looking_for, religion,
/// personality, hobby_category). Cached for the app session: the provider is
/// not auto-disposed, so it loads once; `ref.invalidate` retries.
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

/// First page of hobbies per category, for the grouped chips on M08. More
/// are reached through the hobby search sheet.
final hobbiesByCategoryProvider = FutureProvider.family<MasterDataPage, String>(
  (ref, categoryId) => ref
      .watch(masterDataRepositoryProvider)
      .page(MasterDataType.hobby, categoryId: categoryId),
  retry: (_, _) => null,
);

/// Labels of options the user picked, kept for the session so chips picked
/// from search still show their names. Keyed by option id.
class PickedLabels extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void remember(Iterable<MasterOption> options) {
    state = {...state, for (final o in options) o.id: o.label};
  }
}

final pickedLabelsProvider =
    NotifierProvider<PickedLabels, Map<String, String>>(PickedLabels.new);
