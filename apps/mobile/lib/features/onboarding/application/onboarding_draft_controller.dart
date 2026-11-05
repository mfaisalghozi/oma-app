import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../data/secure_onboarding_draft_store.dart';
import '../domain/entities/onboarding_draft.dart';
import '../domain/repositories/onboarding_draft_store.dart';

final onboardingDraftStoreProvider = Provider<OnboardingDraftStore>(
  (ref) => SecureOnboardingDraftStore(),
);

/// Narrow so token refreshes don't reload the draft.
final _currentUserIdProvider = Provider<String?>(
  (ref) => switch (ref.watch(sessionControllerProvider).value) {
    SignedIn(:final user) => user.userId,
    _ => null,
  },
);

class OnboardingDraftController extends AsyncNotifier<OnboardingDraft?> {
  @override
  Future<OnboardingDraft?> build() async {
    final userId = ref.watch(_currentUserIdProvider);
    if (userId == null) return null;
    final store = ref.read(onboardingDraftStoreProvider);
    final saved = await store.load();
    if (saved != null && saved.userId == userId) return saved;
    // Another account's draft (shared phone): never show it to this user.
    if (saved != null) await store.clear();
    return OnboardingDraft(userId: userId);
  }

  Future<void> edit(
    OnboardingDraft Function(OnboardingDraft draft) change,
  ) async {
    final current = state.value;
    if (current == null) return;
    final next = change(current);
    await ref.read(onboardingDraftStoreProvider).save(next);
    state = AsyncData(next);
  }

  Future<void> clear() async {
    await ref.read(onboardingDraftStoreProvider).clear();
    final userId = state.value?.userId;
    state = AsyncData(userId == null ? null : OnboardingDraft(userId: userId));
  }
}

final onboardingDraftProvider =
    AsyncNotifierProvider<OnboardingDraftController, OnboardingDraft?>(
      OnboardingDraftController.new,
      retry: (_, _) => null,
    );
