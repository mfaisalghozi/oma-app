import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/api/api_client.dart';
import '../domain/entities/auth_session.dart';
import '../domain/repositories/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository, AccessTokenSource {
  SupabaseAuthRepository(this._auth);

  final sb.GoTrueClient _auth;

  @override
  AuthSession? get currentSession => _map(_auth.currentSession);

  @override
  Stream<AuthSession?> sessionChanges() =>
      _auth.onAuthStateChange.map((state) => _map(state.session));

  @override
  Future<String?> accessToken() async => _auth.currentSession?.accessToken;

  @override
  Future<bool> refreshSession() => refresh();

  @override
  Future<bool> refresh() async {
    try {
      final res = await _auth.refreshSession();
      return res.session != null;
    } on sb.AuthException {
      return false;
    }
  }

  @override
  Future<void> onUnauthorized() => signOut();

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on sb.AuthException {
      // Already signed out on the server: the local session is cleared anyway.
    }
  }

  static AuthSession? _map(sb.Session? session) {
    final user = session?.user;
    if (user == null) return null;
    return AuthSession(
      userId: user.id,
      email: user.email,
      emailConfirmed:
          user.email == null ||
          user.emailConfirmedAt != null ||
          user.appMetadata['provider'] != 'email',
    );
  }
}
