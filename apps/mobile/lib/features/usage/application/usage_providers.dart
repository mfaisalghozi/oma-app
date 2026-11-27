import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/api_usage_repository.dart';
import '../domain/entities/daily_usage.dart';
import '../domain/repositories/usage_repository.dart';

final usageRepositoryProvider = Provider<UsageRepository>(
  (ref) => ApiUsageRepository(ref.watch(apiClientProvider)),
);

class DailyUsageController extends AsyncNotifier<DailyUsage> {
  @override
  Future<DailyUsage> build() => ref.watch(usageRepositoryProvider).fetch();

  /// A failed refresh keeps the last known balance: the pill stays useful and
  /// the next successful read corrects it.
  Future<void> refresh() async {
    final previous = state.value;
    final next = await AsyncValue.guard(
      () => ref.read(usageRepositoryProvider).fetch(),
    );
    state = next.hasError && previous != null ? AsyncData(previous) : next;
  }

  /// Optimistic decrement after the server accepts a like.
  void spendLike() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(likes: current.likes.spend()));
  }
}

final dailyUsageProvider =
    AsyncNotifierProvider<DailyUsageController, DailyUsage>(
      DailyUsageController.new,
      retry: (_, _) => null,
    );
