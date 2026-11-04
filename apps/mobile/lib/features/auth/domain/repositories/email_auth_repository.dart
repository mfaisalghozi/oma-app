/// Email sign-in and sign-up.
///
/// OPEN QUESTION (flagged on ONB-FE-04): the BE Technical Doc says Email
/// OTP, while design v0.1 and the SA-FE use email + password + a
/// confirmation link. The screens follow design v0.1 and talk only to this
/// interface through EmailAuthController, so moving to OTP means a new
/// implementation (Supabase `signInWithOtp` + `verifyOTP`) plus a code-entry
/// screen, without touching the session, gates or the rest of onboarding.
abstract interface class EmailAuthRepository {
  /// Throws AuthFailure: invalidCredentials, emailNotConfirmed, network...
  Future<void> signIn({required String email, required String password});

  /// Creates the account and sends the confirmation link. Returns normally
  /// for an address that is already registered too (no email enumeration).
  Future<void> signUp({required String email, required String password});

  Future<void> resendConfirmation(String email);

  /// Sends the reset link. Succeeds for unknown addresses too.
  Future<void> sendPasswordReset(String email);
}
