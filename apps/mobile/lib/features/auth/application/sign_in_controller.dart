import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import 'auth_providers.dart';

enum SocialProvider { google, apple }

class SignInState {
  const SignInState({this.busy, this.error, this.last});

  final SocialProvider? busy;
  final AuthFailure? error;

  final SocialProvider? last;
}

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
