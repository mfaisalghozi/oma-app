/// OPEN: the BE doc says email OTP, design v0.1 says password + confirmation
/// link. Switching to OTP is a new implementation of this interface plus a
/// code-entry screen.
abstract interface class EmailAuthRepository {
  Future<void> signIn({required String email, required String password});

  /// Succeeds for already-registered addresses too (no email enumeration).
  Future<void> signUp({required String email, required String password});

  Future<void> resendConfirmation(String email);

  /// Succeeds for unknown addresses too.
  Future<void> sendPasswordReset(String email);
}
