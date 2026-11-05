import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/app/app.dart';
import 'package:oma_app/core/theme/oma_theme.dart';
import 'package:oma_app/features/auth/presentation/splash_screen.dart';
import 'package:oma_app/features/auth/presentation/welcome_screen.dart';
import 'package:oma_app/features/auth/presentation/widgets/splash_intro.dart';

import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

void main() {
  final signedOut = baseOverrides(
    auth: FakeAuthRepository(),
    accounts: FakeAccountRepository(account()),
  );

  testWidgets('intro finishes within 1.5 s', (tester) async {
    await pumpScreen(tester, const Scaffold(body: SplashIntro()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    final tag = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Ocean Match'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(tag.opacity, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduce motion shows the final frame at once', (tester) async {
    await loadAppFonts();
    await tester.pumpWidget(
      MaterialApp(
        theme: OmaTheme.lagoon(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: SplashIntro()),
        ),
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
    final tag = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Ocean Match'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(tag.opacity, 1);
  });

  testWidgets('session resolving first cuts the intro short', (tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: signedOut, child: const OmaApp()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('both Welcome CTAs open the sign-in hub', (tester) async {
    for (final cta in ['Get started', 'I already have an account']) {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: signedOut,
          child: const OmaApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(cta));
      await tester.pumpAndSettle();
      expect(find.textContaining('M02'), findsOneWidget, reason: cta);
    }
  });

  goldenBothThemes('m00_splash', (tester, theme) async {
    await pumpScreen(
      tester,
      const SplashScreen(),
      theme: theme,
      overrides: baseOverrides(
        auth: FakeAuthRepository(testUser),
        // Never completes, so the splash stays up.
        accounts: _NeverAccountRepository(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
  });

  goldenBothThemes('m01_welcome', (tester, theme) async {
    await pumpScreen(
      tester,
      const WelcomeScreen(),
      theme: theme,
      overrides: signedOut,
    );
    await tester.pumpAndSettle();
  });
}

class _NeverAccountRepository extends FakeAccountRepository {
  _NeverAccountRepository() : super(account());

  @override
  Future<Never> initialize() => Completer<Never>().future;
}
