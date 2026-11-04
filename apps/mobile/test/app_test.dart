import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/app/app.dart';
import 'package:oma_app/features/auth/domain/entities/account_state.dart';

import 'helpers/fakes.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeAuthRepository auth,
    required FakeAccountRepository accounts,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(auth: auth, accounts: accounts),
        child: const OmaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signed-out cold start lands on Welcome', (tester) async {
    await pumpApp(
      tester,
      auth: FakeAuthRepository(),
      accounts: FakeAccountRepository(account()),
    );
    expect(find.textContaining('M01'), findsOneWidget);
  });

  testWidgets('new account lands on Consent', (tester) async {
    await pumpApp(
      tester,
      auth: FakeAuthRepository(testUser),
      accounts: FakeAccountRepository(account(next: NextAction.acceptConsents)),
    );
    expect(find.textContaining('M05'), findsOneWidget);
  });

  testWidgets('returning user lands on Discover', (tester) async {
    await pumpApp(
      tester,
      auth: FakeAuthRepository(testUser),
      accounts: FakeAccountRepository(account(next: NextAction.discovery)),
    );
    expect(find.textContaining('M12'), findsOneWidget);
  });

  testWidgets('sign-out from Discover returns to Welcome', (tester) async {
    await pumpApp(
      tester,
      auth: FakeAuthRepository(testUser),
      accounts: FakeAccountRepository(account(next: NextAction.discovery)),
    );
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.textContaining('M01'), findsOneWidget);
  });

  testWidgets('Deep Sea theme builds', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(
      tester,
      auth: FakeAuthRepository(),
      accounts: FakeAccountRepository(account()),
    );
    final ctx = tester.element(find.textContaining('M01'));
    expect(Theme.of(ctx).brightness, Brightness.dark);
  });
}
