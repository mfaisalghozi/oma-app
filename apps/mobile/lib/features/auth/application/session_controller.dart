import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/account_state.dart';
import '../domain/entities/auth_session.dart';
import '../../onboarding/application/onboarding_draft_controller.dart';
import 'auth_providers.dart';

sealed class AppSession {
  const AppSession();
}

final class SignedOut extends AppSession {
  const SignedOut();
}

final class SignedIn extends AppSession {
  const SignedIn(this.user, this.account);

  final AuthSession user;
  final AccountState account;
}

class SessionController extends AsyncNotifier<AppSession> {
  StreamSubscription<AuthSession?>? _authSub;
  AppLifecycleListener? _lifecycle;

  @override
  Future<AppSession> build() async {
    final auth = ref.watch(authRepositoryProvider);
    _authSub = auth.sessionChanges().listen(_onAuthChanged);
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(refresh()));
    ref.onDispose(() {
      _authSub?.cancel();
      _lifecycle?.dispose();
    });
    return _resolve(auth.currentSession);
  }

  Future<void> refresh() async {
    final user = ref.read(authRepositoryProvider).currentSession;
    final next = await AsyncValue.guard(() => _resolve(user));
    // Keep the current screen on a failed background refresh.
    if (next.hasError && state.hasValue) return;
    state = next;
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    await refresh();
  }

  Future<void> signOut() async {
    await ref.read(onboardingDraftStoreProvider).clear();
    await ref.read(authRepositoryProvider).signOut();
  }

  Future<AppSession> _resolve(AuthSession? user) async {
    if (user == null || !user.emailConfirmed) return const SignedOut();
    final account = await ref.read(accountRepositoryProvider).initialize();
    return SignedIn(user, account);
  }

  Future<void> _onAuthChanged(AuthSession? user) async {
    final current = state.value;
    final unchanged = switch (current) {
      SignedOut() => user == null || !user.emailConfirmed,
      SignedIn(user: final u) => user == u,
      null => false,
    };
    // Token refreshes and the initial event repeat the same user: no reload.
    if (unchanged) return;
    if (user != null && user.emailConfirmed) {
      ref.read(pendingEmailConfirmationProvider.notifier).set(null);
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _resolve(user));
  }
}

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, AppSession>(
      SessionController.new,
      retry: (_, _) => null,
    );
