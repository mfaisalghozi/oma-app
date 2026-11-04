import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_providers.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/domain/usecases/resolve_start_route.dart';
import '../features/auth/presentation/check_inbox_screen.dart';
import '../features/auth/presentation/email_sign_in_screen.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/discover/presentation/discover_screen.dart';
import '../features/onboarding/application/onboarding_resume.dart';
import '../features/onboarding/domain/entities/onboarding_step.dart';
import '../features/onboarding/presentation/consent_screen.dart';
import '../features/onboarding/presentation/profile_setup_screen.dart';
import '../features/onboarding/presentation/steps/about_you_screen.dart';
import '../features/onboarding/presentation/steps/basics_screen.dart';
import '../features/onboarding/presentation/steps/location_screen.dart';
import '../features/onboarding/presentation/steps/notifications_screen.dart';
import '../features/onboarding/presentation/steps/personality_screen.dart';
import '../features/onboarding/presentation/steps/photos_screen.dart';
import '../features/safety/presentation/restricted_screen.dart';
import 'routes.dart';

/// Snapshot of the gate inputs from the providers.
GateState readGateState(Ref ref) {
  final session = ref.read(sessionControllerProvider);
  final value = session.value;
  if (value == null) {
    return session.hasError && !session.isLoading
        ? const GateError()
        : const GateLoading();
  }
  return switch (value) {
    SignedOut() => GateSignedOut(
      pendingEmailConfirmation:
          ref.read(pendingEmailConfirmationProvider) != null,
    ),
    SignedIn(:final account) => GateSignedIn(
      account,
      onboardingResumePath: ref.read(onboardingResumePathProvider),
    ),
  };
}

/// Re-runs the redirect whenever a gate input changes.
class _GateRefresh extends ChangeNotifier {
  _GateRefresh(Ref ref) {
    ref
      ..listen(sessionControllerProvider, (_, _) => notifyListeners())
      ..listen(pendingEmailConfirmationProvider, (_, _) => notifyListeners())
      ..listen(onboardingResumePathProvider, (_, _) => notifyListeners());
  }
}

Widget _onboardingStep(OnboardingStep step) => switch (step) {
  OnboardingStep.basics => const BasicsScreen(),
  OnboardingStep.about => const AboutYouScreen(),
  OnboardingStep.personality => const PersonalityScreen(),
  OnboardingStep.photos => const PhotosScreen(),
  OnboardingStep.location => const LocationScreen(),
  OnboardingStep.notifications => const NotificationsScreen(),
  OnboardingStep.setup => const ProfileSetupScreen(),
};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _GateRefresh(ref);
  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => resolveStartRoute(
      location: state.matchedLocation,
      gate: readGateState(ref),
    ),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(
        path: Routes.signInEmail,
        builder: (_, _) => const EmailSignInScreen(),
      ),
      GoRoute(
        path: Routes.signUpEmail,
        builder: (_, _) => const EmailSignInScreen(createAccount: true),
      ),
      GoRoute(
        path: Routes.checkInbox,
        builder: (_, _) => const CheckInboxScreen(),
      ),
      // The confirmation link lands here; supabase_flutter turns it into a
      // session and the gates move on from the splash.
      GoRoute(
        path: Routes.authCallback,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(path: Routes.consent, builder: (_, _) => const ConsentScreen()),
      GoRoute(
        path: '${Routes.onboarding}/:step',
        redirect: (_, state) =>
            OnboardingStep.fromPath(state.pathParameters['step']) == null
            ? ref.read(onboardingResumePathProvider)
            : null,
        builder: (_, state) => _onboardingStep(
          OnboardingStep.fromPath(state.pathParameters['step'])!,
        ),
      ),
      GoRoute(path: Routes.discover, builder: (_, _) => const DiscoverScreen()),
      GoRoute(
        path: Routes.restricted,
        builder: (_, _) => const RestrictedScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
