import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/errors/failure.dart';

AuthFailure mapAuthException(sb.AuthException e) {
  if (e is sb.AuthRetryableFetchException) {
    return const AuthFailure(AuthFailureKind.network);
  }
  final kind = switch (e.code) {
    'invalid_credentials' => AuthFailureKind.invalidCredentials,
    'email_not_confirmed' => AuthFailureKind.emailNotConfirmed,
    'weak_password' => AuthFailureKind.weakPassword,
    'over_request_rate_limit' ||
    'over_email_send_rate_limit' => AuthFailureKind.rateLimited,
    _ => AuthFailureKind.unknown,
  };
  return AuthFailure(kind, e.code ?? '');
}
