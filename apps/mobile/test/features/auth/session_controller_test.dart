import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/auth/application/auth_providers.dart';
import 'package:oma_app/features/auth/application/session_controller.dart';
import 'package:oma_app/features/auth/domain/entities/account_state.dart';
import 'package:oma_app/features/auth/domain/entities/auth_session.dart';

import '../../helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthRepository auth;
  late FakeAccountRepository accounts;
  late ProviderContainer container;

  ProviderContainer create() {
    final c = ProviderContainer(
      overrides: baseOverrides(auth: auth, accounts: accounts),
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    auth = FakeAuthRepository();
    accounts = FakeAccountRepository(account());
  });

  test(
    'no restored session resolves to SignedOut without calling the API',
    () async {
      container = create();
      expect(
        await container.read(sessionControllerProvider.future),
        isA<SignedOut>(),
      );
      expect(accounts.calls, 0);
    },
  );

  test('restored session calls initialize on cold start', () async {
    auth = FakeAuthRepository(testUser);
    container = create();
    final s = await container.read(sessionControllerProvider.future);
    expect(s, isA<SignedIn>());
    expect((s as SignedIn).account.nextAction, NextAction.completeOnboarding);
    expect(accounts.calls, 1);
  });

  test('sign-in calls initialize and clears a pending email', () async {
    container = create();
    await container.read(sessionControllerProvider.future);
    container.read(pendingEmailConfirmationProvider.notifier).set('a@b.c');

    auth.emit(testUser);
    await pumpEventQueue();

    expect(container.read(sessionControllerProvider).value, isA<SignedIn>());
    expect(accounts.calls, 1);
    expect(container.read(pendingEmailConfirmationProvider), isNull);
  });

  test('a token refresh for the same user does not re-initialize', () async {
    auth = FakeAuthRepository(testUser);
    container = create();
    await container.read(sessionControllerProvider.future);
    auth.emit(testUser);
    await pumpEventQueue();
    expect(accounts.calls, 1);
  });

  test('unconfirmed email sign-up stays signed out', () async {
    auth = FakeAuthRepository(
      const AuthSession(userId: 'u1', email: 'a@b.c', emailConfirmed: false),
    );
    container = create();
    expect(
      await container.read(sessionControllerProvider.future),
      isA<SignedOut>(),
    );
    expect(accounts.calls, 0);
  });

  test('sign-out returns to SignedOut', () async {
    auth = FakeAuthRepository(testUser);
    container = create();
    await container.read(sessionControllerProvider.future);
    await container.read(sessionControllerProvider.notifier).signOut();
    await pumpEventQueue();
    expect(container.read(sessionControllerProvider).value, isA<SignedOut>());
  });

  test('refresh picks up a new next_action without the splash', () async {
    auth = FakeAuthRepository(testUser);
    accounts.result = account(next: NextAction.acceptConsents);
    container = create();
    await container.read(sessionControllerProvider.future);

    accounts.result = account();
    await container.read(sessionControllerProvider.notifier).refresh();
    final s = container.read(sessionControllerProvider).value! as SignedIn;
    expect(s.account.nextAction, NextAction.completeOnboarding);
  });

  test('failed background refresh keeps the current state', () async {
    auth = FakeAuthRepository(testUser);
    container = create();
    await container.read(sessionControllerProvider.future);

    accounts.result = const NetworkFailure();
    await container.read(sessionControllerProvider.notifier).refresh();
    expect(container.read(sessionControllerProvider).value, isA<SignedIn>());
  });

  test('cold start failure surfaces an error, retry recovers', () async {
    auth = FakeAuthRepository(testUser);
    accounts.result = const NetworkFailure();
    container = create();
    await expectLater(
      container.read(sessionControllerProvider.future),
      throwsA(isA<NetworkFailure>()),
    );

    accounts.result = account();
    await container.read(sessionControllerProvider.notifier).retry();
    expect(container.read(sessionControllerProvider).value, isA<SignedIn>());
  });
}
