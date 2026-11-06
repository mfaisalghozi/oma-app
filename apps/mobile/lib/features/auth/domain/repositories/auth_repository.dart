import '../entities/auth_session.dart';

abstract interface class AuthRepository {
  AuthSession? get currentSession;

  Stream<AuthSession?> sessionChanges();

  Future<String?> accessToken();

  Future<bool> refreshSession();

  Future<void> signOut();
}
