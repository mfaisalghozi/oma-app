import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/api_usage_repository.dart';
import '../domain/entities/daily_usage.dart';
import '../domain/repositories/usage_repository.dart';

final usageRepositoryProvider = Provider<UsageRepository>(
  (ref) => ApiUsageRepository(ref.watch(apiClientProvider)),
);

class DailyUsageController extends AsyncNotifier<DailyUsage> {
  Timer? _reset;

  @override
  Future<DailyUsage> build() async {
    ref.onDispose(() => _reset?.cancel());
    final usage = await ref.watch(usageRepositoryProvider).fetch();
    _scheduleReset(usage.resetsAt);
    return usage;
  }

  /// The grant resets at WIB midnight, sent as `resets_at`. When it passes the
  /// pill and the Out of likes state must clear on their own.
  void _scheduleReset(DateTime at) {
    _reset?.cancel();
    final delay = at.difference(DateTime.now());
    if (delay.isNegative) return;
    _reset = Timer(delay + const Duration(seconds: 1), () {
      unawaited(refresh());
    });
  }

  /// A failed refresh keeps the last known balance: the pill stays useful and
  /// the next successful read corrects it.
  Future<void> refresh() async {
    final previous = state.value;
    final next = await AsyncValue.guard(
      () => ref.read(usageRepositoryProvider).fetch(),
    );
    state = next.hasError && previous != null ? AsyncData(previous) : next;
    final fresh = state.value;
    if (fresh != null) _scheduleReset(fresh.resetsAt);
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
