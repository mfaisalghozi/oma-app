import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/config/app_config.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/auth/application/auth_providers.dart';
import 'package:oma_app/features/auth/domain/repositories/social_auth_repository.dart';
import 'package:oma_app/features/auth/presentation/sign_in_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

class FakeSocialAuth implements SocialAuthRepository {
  FakeSocialAuth({this.apple = true});

  final bool apple;
  Object? next;
  final calls = <String>[];

  @override
  bool get appleAvailable => apple;

  Future<void> _run(String name) async {
    calls.add(name);
    final n = next;
    if (n != null) throw n;
  }

  @override
  Future<void> signInWithGoogle() => _run('google');

  @override
  Future<void> signInWithApple() => _run('apple');
}

void main() {
  late FakeSocialAuth social;

  setUp(() => social = FakeSocialAuth());

  Future<void> pump(
    WidgetTester tester, {
    GoldenTheme theme = GoldenTheme.lagoon,
    AppConfig config = testConfig,
  }) async {
    await pumpScreen(
      tester,
      const SignInScreen(),
      theme: theme,
      overrides: [
        appConfigProvider.overrideWithValue(config),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        socialAuthRepositoryProvider.overrideWithValue(social),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Google and Apple call their native flows', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Apple'));
    await tester.pumpAndSettle();
    expect(social.calls, ['google', 'apple']);
  });

  testWidgets('user cancel returns to M02 silently', (tester) async {
    social.next = const AuthFailure(AuthFailureKind.cancelled);
    await pump(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('an error shows a message with Try again', (tester) async {
    social.next = const AuthFailure(AuthFailureKind.unknown);
    await pump(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining("couldn't sign you in"), findsOneWidget);

    social.next = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(social.calls, ['google', 'google']);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('phone is hidden unless AUTH_PHONE_ENABLED', (tester) async {
    await pump(tester);
    expect(find.text('Continue with phone number'), findsNothing);
  });

  testWidgets('phone shows when the flag is on', (tester) async {
    await pump(
      tester,
      config: const AppConfig(
        flavor: 'test',
        supabaseUrl: 'x',
        supabasePublishableKey: 'x',
        apiBaseUrl: 'x',
        authRedirectUrl: 'x',
        authPhoneEnabled: true,
      ),
    );
    expect(find.text('Continue with phone number'), findsOneWidget);
  });

  testWidgets('Apple is hidden where it is unavailable', (tester) async {
    social = FakeSocialAuth(apple: false);
    await pump(tester);
    expect(find.text('Continue with Apple'), findsNothing);
  });

  goldenBothThemes('m02_sign_in', (tester, theme) async {
    await pump(tester, theme: theme);
  });

  goldenBothThemes('m02_sign_in_error', (tester, theme) async {
    social.next = const AuthFailure(AuthFailureKind.network);
    await pump(tester, theme: theme);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
  });
}
