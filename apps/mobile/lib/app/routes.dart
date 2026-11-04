abstract final class Routes {
  static const splash = '/splash'; // M00
  static const welcome = '/welcome'; // M01
  static const signIn = '/sign-in'; // M02
  static const signInEmail = '/sign-in/email'; // M04
  static const signUpEmail = '/sign-in/email/create'; // M04b
  static const checkInbox = '/sign-in/email/check-inbox'; // M04c
  static const authCallback = '/auth/callback'; // confirmation deep link

  static const onboarding = '/onboarding';
  static const consent = '/onboarding/consent'; // M05
  static String onboardingStep(String step) => '/onboarding/$step';

  static const discover = '/discover'; // M12 (not in this feature)
  static const restricted = '/restricted'; // M26 / frozen prompt

  static const public = {
    welcome,
    signIn,
    signInEmail,
    signUpEmail,
    checkInbox,
    authCallback,
  };
}
