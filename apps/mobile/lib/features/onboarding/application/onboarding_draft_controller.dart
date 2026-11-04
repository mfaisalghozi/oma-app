import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/session_controller.dart';
import '../data/secure_onboarding_draft_store.dart';
import '../domain/entities/onboarding_draft.dart';
import '../domain/repositories/onboarding_draft_store.dart';

final onboardingDraftStoreProvider = Provider<OnboardingDraftStore>(
  (ref) => SecureOnboardingDraftStore(),
);

/// The signed-in user's id, or null. Narrow so token refreshes don't reload
/// the draft.
final _currentUserIdProvider = Provider<String?>(
  (ref) => switch (ref.watch(sessionControllerProvider).value) {
    SignedIn(:final user) => user.userId,
    _ => null,
  },
);

/// The current user's onboarding answers. Null when nobody is signed in.
///
/// Taps and picks are written to secure storage before the state updates, so
/// killing the app at any point resumes with the answers intact. Typing is
/// saved [typingDelay] after the last keystroke.
class OnboardingDraftController extends AsyncNotifier<OnboardingDraft?> {
  static const typingDelay = Duration(milliseconds: 400);
  Timer? _pending;

  /// The typed change waiting for [_pending], saved on dispose too.
  OnboardingDraft? _unsaved;

  @override
  Future<OnboardingDraft?> build() async {
    final store = ref.read(onboardingDraftStoreProvider);
    ref.onDispose(() {
      _pending?.cancel();
      final d = _unsaved;
      _unsaved = null;
      if (d != null) unawaited(store.save(d));
    });
    final userId = ref.watch(_currentUserIdProvider);
    if (userId == null) return null;
    final saved = await store.load();
    if (saved != null && saved.userId == userId) return saved;
    // Another account's draft (shared phone): never show it to this user.
    if (saved != null) await store.clear();
    return OnboardingDraft(userId: userId);
  }

  /// Applies [change] and persists it. No-op while signed out or loading.
  Future<void> edit(
    OnboardingDraft Function(OnboardingDraft draft) change,
  ) async {
    final current = state.value;
    if (current == null) return;
    _pending?.cancel();
    _unsaved = null;
    final next = change(current);
    await ref.read(onboardingDraftStoreProvider).save(next);
    state = AsyncData(next);
  }

  /// For text fields: updates now, saves after a short pause in typing.
  void editTyping(OnboardingDraft Function(OnboardingDraft draft) change) {
    final current = state.value;
    if (current == null) return;
    final next = change(current);
    state = AsyncData(next);
    _unsaved = next;
    _pending?.cancel();
    _pending = Timer(typingDelay, flush);
  }

  /// Saves a pending typed change now (Next, back, app paused).
  Future<void> flush() async {
    _pending?.cancel();
    final d = _unsaved;
    _unsaved = null;
    if (d != null) await ref.read(onboardingDraftStoreProvider).save(d);
  }

  /// After a successful submit, sign-out or account deletion.
  Future<void> clear() async {
    _pending?.cancel();
    _unsaved = null;
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
