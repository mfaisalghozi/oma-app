import '../../../../app/routes.dart';
import '../entities/account_state.dart';

/// Everything the gates need to decide where the user may be.
sealed class GateState {
  const GateState();
}

/// Session restore or `POST /v1/me/initialize` is still running.
final class GateLoading extends GateState {
  const GateLoading();
}

/// Bootstrap failed (for example no connection on cold start).
final class GateError extends GateState {
  const GateError();
}

final class GateSignedOut extends GateState {
  const GateSignedOut({this.pendingEmailConfirmation = false});

  /// An email sign-up is waiting for its confirmation link (M04c).
  final bool pendingEmailConfirmation;
}

final class GateSignedIn extends GateState {
  const GateSignedIn(this.account, {required this.onboardingResumePath});

  final AccountState account;

  /// First unfinished onboarding step (ResumeOnboarding).
  final String onboardingResumePath;
}

/// ResolveStartRoute: the gate order from the architecture doc and SA-FE
/// section 6, run by go_router's `redirect` on every navigation and resume.
///
/// 1. No session: Welcome (or M04c while an email sign-up awaits its link).
/// 2. Suspended or frozen: the restricted screen only.
/// 3. Consent missing: M05.
/// 4. Onboarding incomplete: the first unfinished step.
/// 5. Otherwise: Discover, or wherever the user was going.
///
/// Returns the path to redirect to, or null to let the navigation through.
String? resolveStartRoute({required String location, required GateState gate}) {
  String? goTo(String target) => location == target ? null : target;

  switch (gate) {
    case GateLoading():
    case GateError():
      return goTo(Routes.splash);

    case GateSignedOut(:final pendingEmailConfirmation):
      if (pendingEmailConfirmation &&
          !location.startsWith(Routes.signInEmail)) {
        return Routes.checkInbox;
      }
      if (Routes.public.contains(location)) return null;
      return Routes.welcome;

    case GateSignedIn(:final account, :final onboardingResumePath):
      if (account.isRestricted) return goTo(Routes.restricted);
      switch (account.nextAction) {
        case NextAction.acceptConsents:
          return goTo(Routes.consent);
        case NextAction.completeOnboarding:
          final inSteps =
              location.startsWith('${Routes.onboarding}/') &&
              location != Routes.consent;
          return inSteps ? null : onboardingResumePath;
        case NextAction.discovery:
          final outsideApp =
              location == Routes.splash ||
              location == Routes.restricted ||
              Routes.public.contains(location) ||
              location.startsWith(Routes.onboarding);
          return outsideApp ? Routes.discover : null;
        case NextAction.accountRestricted:
          return goTo(Routes.restricted);
      }
  }
}
