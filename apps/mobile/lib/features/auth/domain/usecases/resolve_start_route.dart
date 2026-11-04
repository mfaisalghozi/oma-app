import '../../../../app/routes.dart';
import '../entities/account_state.dart';

sealed class GateState {
  const GateState();
}

final class GateLoading extends GateState {
  const GateLoading();
}

final class GateError extends GateState {
  const GateError();
}

final class GateSignedOut extends GateState {
  const GateSignedOut({this.pendingEmailConfirmation = false});

  final bool pendingEmailConfirmation;
}

final class GateSignedIn extends GateState {
  const GateSignedIn(this.account, {required this.onboardingResumePath});

  final AccountState account;

  final String onboardingResumePath;
}

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
