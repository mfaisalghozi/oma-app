import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../domain/entities/password_rules.dart';
import 'auth_providers.dart';

sealed class EmailAuthError {
  const EmailAuthError();
}

final class InvalidEmail extends EmailAuthError {
  const InvalidEmail();
}

final class WrongPassword extends EmailAuthError {
  const WrongPassword(this.triesLeft);

  final int triesLeft;
}

final class LockedOut extends EmailAuthError {
  const LockedOut(this.until);

  final DateTime until;
}

final class EmailAuthOffline extends EmailAuthError {
  const EmailAuthOffline();
}

final class EmailAuthRateLimited extends EmailAuthError {
  const EmailAuthRateLimited();
}

final class EmailAuthUnknown extends EmailAuthError {
  const EmailAuthUnknown();
}

class EmailAuthState {
  const EmailAuthState({this.busy = false, this.error, this.notice});

  final bool busy;
  final EmailAuthError? error;

  final String? notice;
}

enum EmailAuthOutcome { none, checkInbox }

class EmailAuthController extends Notifier<EmailAuthState> {
  @override
  EmailAuthState build() => const EmailAuthState();

  DateTime get _now => ref.read(clockProvider)();

  Future<EmailAuthOutcome> signIn(String email, String password) async {
    if (state.busy) return EmailAuthOutcome.none;
    if (!looksLikeEmail(email)) {
      state = const EmailAuthState(error: InvalidEmail());
      return EmailAuthOutcome.none;
    }
    final store = ref.read(lockoutStoreProvider);
    var lockout = (await store.read(email)).refresh(_now);
    if (lockout.isLocked(_now)) {
      state = EmailAuthState(error: LockedOut(lockout.lockedUntil!));
      return EmailAuthOutcome.none;
    }

    state = const EmailAuthState(busy: true);
    try {
      await ref
          .read(emailAuthRepositoryProvider)
          .signIn(email: email, password: password);
      await store.clear(email);
      state = const EmailAuthState();
      return EmailAuthOutcome.none;
    } on AuthFailure catch (e) {
      switch (e.kind) {
        case AuthFailureKind.invalidCredentials:
          lockout = lockout.recordFailure(_now);
          await store.write(email, lockout);
          state = EmailAuthState(
            error: lockout.isLocked(_now)
                ? LockedOut(lockout.lockedUntil!)
                : WrongPassword(lockout.triesLeft),
          );
          return EmailAuthOutcome.none;
        case AuthFailureKind.emailNotConfirmed:
          ref.read(pendingEmailConfirmationProvider.notifier).set(email.trim());
          state = const EmailAuthState();
          return EmailAuthOutcome.checkInbox;
        default:
          state = EmailAuthState(error: _map(e));
          return EmailAuthOutcome.none;
      }
    }
  }

  Future<EmailAuthOutcome> signUp(String email, String password) async {
    if (state.busy) return EmailAuthOutcome.none;
    if (!looksLikeEmail(email)) {
      state = const EmailAuthState(error: InvalidEmail());
      return EmailAuthOutcome.none;
    }
    if (!PasswordRules(password).valid) return EmailAuthOutcome.none;
    state = const EmailAuthState(busy: true);
    try {
      await ref
          .read(emailAuthRepositoryProvider)
          .signUp(email: email, password: password);
      ref.read(pendingEmailConfirmationProvider.notifier).set(email.trim());
      state = const EmailAuthState();
      return EmailAuthOutcome.checkInbox;
    } on AuthFailure catch (e) {
      state = EmailAuthState(error: _map(e));
      return EmailAuthOutcome.none;
    }
  }

  Future<void> forgotPassword(String email) async {
    if (!looksLikeEmail(email)) {
      state = const EmailAuthState(error: InvalidEmail());
      return;
    }
    state = const EmailAuthState(busy: true);
    try {
      await ref.read(emailAuthRepositoryProvider).sendPasswordReset(email);
      state = const EmailAuthState(
        notice:
            'If an account uses this email, we sent a link to reset the '
            'password.',
      );
    } on AuthFailure catch (e) {
      state = EmailAuthState(error: _map(e));
    }
  }

  void clear() => state = const EmailAuthState();

  static EmailAuthError _map(AuthFailure e) => switch (e.kind) {
    AuthFailureKind.network => const EmailAuthOffline(),
    AuthFailureKind.rateLimited => const EmailAuthRateLimited(),
    _ => const EmailAuthUnknown(),
  };
}

final emailAuthControllerProvider =
    NotifierProvider.autoDispose<EmailAuthController, EmailAuthState>(
      EmailAuthController.new,
    );

class ResendController extends Notifier<ResendState> {
  static const cooldown = Duration(seconds: 45);

  @override
  ResendState build() =>
      ResendState(availableAt: ref.read(clockProvider)().add(cooldown));

  Future<void> resend(String email) async {
    if (state.busy) return;
    state = ResendState(availableAt: state.availableAt, busy: true);
    try {
      await ref.read(emailAuthRepositoryProvider).resendConfirmation(email);
      state = ResendState(
        availableAt: ref.read(clockProvider)().add(cooldown),
        sent: true,
      );
    } on AuthFailure catch (e) {
      state = ResendState(
        availableAt: state.availableAt,
        error: e.kind == AuthFailureKind.rateLimited
            ? const EmailAuthRateLimited()
            : e.kind == AuthFailureKind.network
            ? const EmailAuthOffline()
            : const EmailAuthUnknown(),
      );
    }
  }
}

class ResendState {
  const ResendState({
    required this.availableAt,
    this.busy = false,
    this.sent = false,
    this.error,
  });

  final DateTime availableAt;
  final bool busy;
  final bool sent;
  final EmailAuthError? error;
}

final resendControllerProvider =
    NotifierProvider.autoDispose<ResendController, ResendState>(
      ResendController.new,
    );
