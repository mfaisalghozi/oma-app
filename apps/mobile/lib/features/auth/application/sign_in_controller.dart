import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import 'auth_providers.dart';

enum SocialProvider { google, apple }

/// M02 state: which provider is in flight and the last error, if any.
class SignInState {
  const SignInState({this.busy, this.error, this.last});

  final SocialProvider? busy;
  final AuthFailure? error;

  /// The provider of the last attempt, for Try again.
  final SocialProvider? last;
}

/// Runs a native sign-in. On success the Supabase session changes, the
/// SessionController calls initialize and the gates route the user (new user
/// to M05, returning user to Discover); this controller does not navigate.
class SignInController extends Notifier<SignInState> {
  @override
  SignInState build() => const SignInState();

  Future<void> signIn(SocialProvider provider) async {
    if (state.busy != null) return;
    state = SignInState(busy: provider);
    final repo = ref.read(socialAuthRepositoryProvider);
    try {
      switch (provider) {
        case SocialProvider.google:
          await repo.signInWithGoogle();
        case SocialProvider.apple:
          await repo.signInWithApple();
      }
      state = const SignInState();
    } on AuthFailure catch (e) {
      // User closed the sheet: back to M02 silently.
      state = SignInState(
        error: e.kind == AuthFailureKind.cancelled ? null : e,
        last: provider,
      );
    } catch (_) {
      state = SignInState(
        error: const AuthFailure(AuthFailureKind.unknown),
        last: provider,
      );
    }
  }

  Future<void> retry() async {
    final last = state.last;
    if (last != null) await signIn(last);
  }
}

final signInControllerProvider =
    NotifierProvider.autoDispose<SignInController, SignInState>(
      SignInController.new,
    );
