import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/errors/failure.dart';
import '../domain/repositories/email_auth_repository.dart';
import 'auth_error_mapper.dart';

class SupabaseEmailAuthRepository implements EmailAuthRepository {
  SupabaseEmailAuthRepository(this._auth, {required this.redirectUrl});

  final sb.GoTrueClient _auth;

  final String redirectUrl;

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(
        () => _auth.signInWithPassword(email: email.trim(), password: password),
      );

  @override
  Future<void> signUp({required String email, required String password}) =>
      _guard(
        () => _auth.signUp(
          email: email.trim(),
          password: password,
          emailRedirectTo: redirectUrl,
        ),
      );

  @override
  Future<void> resendConfirmation(String email) => _guard(
    () => _auth.resend(
      type: sb.OtpType.signup,
      email: email.trim(),
      emailRedirectTo: redirectUrl,
    ),
  );

  @override
  Future<void> sendPasswordReset(String email) => _guard(
    () => _auth.resetPasswordForEmail(email.trim(), redirectTo: redirectUrl),
  );

  Future<void> _guard(Future<Object?> Function() call) async {
    try {
      await call();
    } on sb.AuthException catch (e) {
      throw mapAuthException(e);
    } on Failure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(AuthFailureKind.network);
    }
  }
}
