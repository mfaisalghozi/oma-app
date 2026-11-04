import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/core/widgets/oma_button.dart';
import 'package:oma_app/features/auth/application/auth_providers.dart';
import 'package:oma_app/features/auth/application/email_auth_controller.dart';
import 'package:oma_app/features/auth/data/lockout_store.dart';
import 'package:oma_app/features/auth/domain/entities/password_rules.dart';
import 'package:oma_app/features/auth/domain/entities/sign_in_lockout.dart';
import 'package:oma_app/features/auth/domain/repositories/email_auth_repository.dart';
import 'package:oma_app/features/auth/presentation/check_inbox_screen.dart';
import 'package:oma_app/features/auth/presentation/email_sign_in_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

class FakeEmailAuth implements EmailAuthRepository {
  Object? next;
  final calls = <String>[];

  Future<void> _run(String name) async {
    calls.add(name);
    final n = next;
    if (n != null) throw n;
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      _run('signIn');

  @override
  Future<void> signUp({required String email, required String password}) =>
      _run('signUp');

  @override
  Future<void> resendConfirmation(String email) => _run('resend');

  @override
  Future<void> sendPasswordReset(String email) => _run('reset');
}

class MemoryLockoutStore implements LockoutStore {
  final _data = <String, SignInLockout>{};

  @override
  Future<SignInLockout> read(String email) async =>
      _data[email] ?? const SignInLockout();

  @override
  Future<void> write(String email, SignInLockout lockout) async =>
      _data[email] = lockout;

  @override
  Future<void> clear(String email) async => _data.remove(email);
}

void main() {
  late FakeEmailAuth emailAuth;
  late DateTime now;

  List<Override> overrides() => [
    ...baseOverrides(
      auth: FakeAuthRepository(),
      accounts: FakeAccountRepository(account()),
    ),
    emailAuthRepositoryProvider.overrideWithValue(emailAuth),
    lockoutStoreProvider.overrideWithValue(MemoryLockoutStore()),
    clockProvider.overrideWithValue(() => now),
  ];

  setUp(() {
    emailAuth = FakeEmailAuth();
    now = DateTime(2026, 11, 4, 10);
  });

  group('PasswordRules', () {
    test('needs 8+ characters, a letter and a number', () {
      expect(const PasswordRules('abc12').valid, isFalse);
      expect(const PasswordRules('abcdefgh').valid, isFalse);
      expect(const PasswordRules('12345678').valid, isFalse);
      expect(const PasswordRules('abcd1234').valid, isTrue);
    });
  });

  group('EmailAuthController', () {
    late ProviderContainer c;
    late EmailAuthController ctrl;

    setUp(() {
      c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      c.listen(emailAuthControllerProvider, (_, _) {});
      ctrl = c.read(emailAuthControllerProvider.notifier);
    });

    test('wrong password counts down, then pauses 15 minutes', () async {
      emailAuth.next = const AuthFailure(AuthFailureKind.invalidCredentials);
      await ctrl.signIn('a@b.co', 'x');
      expect(
        (c.read(emailAuthControllerProvider).error! as WrongPassword).triesLeft,
        2,
      );
      await ctrl.signIn('a@b.co', 'x');
      await ctrl.signIn('a@b.co', 'x');
      final locked = c.read(emailAuthControllerProvider).error;
      expect(locked, isA<LockedOut>());
      expect(
        (locked! as LockedOut).until,
        now.add(const Duration(minutes: 15)),
      );

      // While paused the API is not called.
      await ctrl.signIn('a@b.co', 'x');
      expect(emailAuth.calls, hasLength(3));

      // After the pause the counter starts again.
      now = now.add(const Duration(minutes: 16));
      emailAuth.next = null;
      await ctrl.signIn('a@b.co', 'right1234');
      expect(c.read(emailAuthControllerProvider).error, isNull);
      expect(emailAuth.calls, hasLength(4));
    });

    test('unconfirmed email goes to M04c', () async {
      emailAuth.next = const AuthFailure(AuthFailureKind.emailNotConfirmed);
      expect(
        await ctrl.signIn('a@b.co', 'abcd1234'),
        EmailAuthOutcome.checkInbox,
      );
      expect(c.read(pendingEmailConfirmationProvider), 'a@b.co');
    });

    test('sign-up sets the pending email and goes to M04c', () async {
      expect(
        await ctrl.signUp('a@b.co', 'abcd1234'),
        EmailAuthOutcome.checkInbox,
      );
      expect(c.read(pendingEmailConfirmationProvider), 'a@b.co');
    });

    test('sign-up with a weak password does not call Supabase', () async {
      await ctrl.signUp('a@b.co', 'short');
      expect(emailAuth.calls, isEmpty);
    });

    test(
      'forgot password sends the reset email with a neutral notice',
      () async {
        await ctrl.forgotPassword('a@b.co');
        expect(emailAuth.calls, ['reset']);
        expect(
          c.read(emailAuthControllerProvider).notice,
          contains('If an account'),
        );
      },
    );

    test('invalid email is caught before the network', () async {
      await ctrl.signIn('not-an-email', 'abcd1234');
      expect(c.read(emailAuthControllerProvider).error, isA<InvalidEmail>());
      expect(emailAuth.calls, isEmpty);
    });
  });

  testWidgets('M04c resend is disabled for 45 s', (tester) async {
    final o = overrides();
    await pumpScreen(tester, const CheckInboxScreen(), overrides: o);
    await tester.pump();
    expect(find.text('Resend link in 0:45'), findsOneWidget);

    now = now.add(const Duration(seconds: 45));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend link'), findsOneWidget);
    await tester.tap(find.text('Resend link'));
    await tester.pump();
    expect(emailAuth.calls, ['resend']);
  });

  goldenBothThemes('m04_email_sign_in_wrong_password', (tester, theme) async {
    emailAuth.next = const AuthFailure(AuthFailureKind.invalidCredentials);
    await pumpScreen(
      tester,
      const EmailSignInScreen(),
      theme: theme,
      overrides: overrides(),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'rania.putri@gmail.com',
    );
    await tester.enterText(find.byType(TextField).at(1), 'wrongpass1');
    await tester.pump();
    await tester.tap(find.widgetWithText(OmaButton, 'Sign in'));
    await tester.pumpAndSettle();
    // ignore: avoid_print
  });

  goldenBothThemes('m04b_create_account', (tester, theme) async {
    await pumpScreen(
      tester,
      const EmailSignInScreen(createAccount: true),
      theme: theme,
      overrides: overrides(),
    );
    await tester.enterText(
      find.byType(TextField).at(0),
      'rania.putri@gmail.com',
    );
    await tester.enterText(find.byType(TextField).at(1), 'ocean2026');
    await tester.pumpAndSettle();
  });

  goldenBothThemes('m04c_check_inbox', (tester, theme) async {
    final o = overrides();
    await pumpScreen(
      tester,
      const CheckInboxScreen(),
      theme: theme,
      overrides: o,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CheckInboxScreen)),
    );
    container
        .read(pendingEmailConfirmationProvider.notifier)
        .set('rania.putri@gmail.com');
    await tester.pump();
  });
}
