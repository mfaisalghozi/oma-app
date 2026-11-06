import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/app/routes.dart';
import 'package:oma_app/features/auth/domain/entities/account_state.dart';
import 'package:oma_app/features/auth/domain/usecases/resolve_start_route.dart';

import '../../helpers/fakes.dart';

void main() {
  const resume = '/onboarding/basics';
  GateSignedIn signedIn(AccountState a) =>
      GateSignedIn(a, onboardingResumePath: resume);

  group('loading and errors', () {
    test('loading holds the user on the splash', () {
      expect(
        resolveStartRoute(location: Routes.signIn, gate: const GateLoading()),
        Routes.splash,
      );
      expect(
        resolveStartRoute(location: Routes.splash, gate: const GateLoading()),
        isNull,
      );
    });

    test('bootstrap error stays on the splash (Try again lives there)', () {
      expect(
        resolveStartRoute(location: Routes.discover, gate: const GateError()),
        Routes.splash,
      );
    });
  });

  group('no session', () {
    test('goes to Welcome from a protected route', () {
      for (final loc in [Routes.splash, Routes.discover, Routes.consent]) {
        expect(
          resolveStartRoute(location: loc, gate: const GateSignedOut()),
          Routes.welcome,
          reason: loc,
        );
      }
    });

    test('public routes are allowed', () {
      for (final loc in Routes.public) {
        expect(
          resolveStartRoute(location: loc, gate: const GateSignedOut()),
          isNull,
          reason: loc,
        );
      }
    });

    test('pending email confirmation reopens M04c', () {
      const gate = GateSignedOut(pendingEmailConfirmation: true);
      expect(
        resolveStartRoute(location: Routes.splash, gate: gate),
        Routes.checkInbox,
      );
      expect(
        resolveStartRoute(location: Routes.checkInbox, gate: gate),
        isNull,
      );
      expect(
        resolveStartRoute(location: Routes.signUpEmail, gate: gate),
        isNull,
      );
    });
  });

  group('next_action', () {
    test('accept_consents lands on M05 and nowhere else', () {
      final gate = signedIn(account(next: NextAction.acceptConsents));
      expect(
        resolveStartRoute(location: Routes.splash, gate: gate),
        Routes.consent,
      );
      expect(resolveStartRoute(location: resume, gate: gate), Routes.consent);
      expect(resolveStartRoute(location: Routes.consent, gate: gate), isNull);
    });

    test('complete_onboarding resumes the first unfinished step', () {
      final gate = signedIn(account());
      expect(resolveStartRoute(location: Routes.splash, gate: gate), resume);
      expect(resolveStartRoute(location: Routes.consent, gate: gate), resume);
      expect(resolveStartRoute(location: Routes.discover, gate: gate), resume);
      expect(
        resolveStartRoute(location: '/onboarding/photos', gate: gate),
        isNull,
      );
    });

    test('discovery lands on Discover', () {
      final gate = signedIn(account(next: NextAction.discovery));
      for (final loc in [
        Routes.splash,
        Routes.signIn,
        resume,
        Routes.consent,
      ]) {
        expect(
          resolveStartRoute(location: loc, gate: gate),
          Routes.discover,
          reason: loc,
        );
      }
      expect(resolveStartRoute(location: Routes.discover, gate: gate), isNull);
    });

    test('account_restricted lands on the restricted screen', () {
      final gate = signedIn(account(next: NextAction.accountRestricted));
      expect(
        resolveStartRoute(location: Routes.discover, gate: gate),
        Routes.restricted,
      );
      expect(
        resolveStartRoute(location: Routes.restricted, gate: gate),
        isNull,
      );
    });

    test('suspended status wins over any next_action', () {
      final gate = signedIn(
        account(next: NextAction.discovery, status: AccountStatus.suspended),
      );
      expect(
        resolveStartRoute(location: Routes.discover, gate: gate),
        Routes.restricted,
      );
    });

    test('frozen status is restricted too', () {
      final gate = signedIn(account(status: AccountStatus.frozen));
      expect(
        resolveStartRoute(location: resume, gate: gate),
        Routes.restricted,
      );
    });
  });

  test('unknown next_action falls back to onboarding', () {
    expect(NextAction.parse('something_new'), NextAction.completeOnboarding);
  });
}
