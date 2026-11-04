import '../entities/auth_session.dart';

/// Session lifecycle over Supabase Auth.
///
/// Sign-in methods live in their own interfaces (social, email) so each method
/// can be swapped without touching the session code. See
/// `email_auth_repository.dart` for why email is abstracted.
abstract interface class AuthRepository {
  /// The restored session, or null when signed out.
  AuthSession? get currentSession;

  /// Emits whenever the user signs in, signs out or the user record changes.
  Stream<AuthSession?> sessionChanges();

  Future<String?> accessToken();

  /// Refreshes the session once. False when it can't be refreshed.
  Future<bool> refreshSession();

  Future<void> signOut();
}
