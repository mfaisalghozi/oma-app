import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../domain/repositories/social_auth_repository.dart';
import 'auth_error_mapper.dart';

/// Native sheets (no browser pop-up), then `signInWithIdToken` on Supabase.
class NativeSocialAuthRepository implements SocialAuthRepository {
  NativeSocialAuthRepository(this._auth, this._config, {GoogleSignIn? google})
    : _google = google ?? GoogleSignIn.instance;

  final sb.GoTrueClient _auth;
  final AppConfig _config;
  final GoogleSignIn _google;
  Future<void>? _googleReady;

  @override
  bool get appleAvailable => Platform.isIOS;

  @override
  Future<void> signInWithGoogle() async {
    try {
      await (_googleReady ??= _google.initialize(
        clientId: _config.googleIosClientId.isEmpty
            ? null
            : _config.googleIosClientId,
        // The web client id makes Google issue an ID token Supabase accepts.
        serverClientId: _config.googleWebClientId.isEmpty
            ? null
            : _config.googleWebClientId,
      ));
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AuthFailure(AuthFailureKind.unknown);
      await _auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: idToken,
      );
    } on GoogleSignInException catch (e) {
      throw switch (e.code) {
        GoogleSignInExceptionCode.canceled => const AuthFailure(
          AuthFailureKind.cancelled,
        ),
        _ => AuthFailure(AuthFailureKind.unknown, e.code.name),
      };
    } on sb.AuthException catch (e) {
      throw mapAuthException(e);
    }
  }

  @override
  Future<void> signInWithApple() async {
    // Apple gets the SHA-256 of the nonce, Supabase gets the raw value and
    // checks they match.
    final rawNonce = _nonce();
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      final idToken = credential.identityToken;
      if (idToken == null) throw const AuthFailure(AuthFailureKind.unknown);
      await _auth.signInWithIdToken(
        provider: sb.OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      throw e.code == AuthorizationErrorCode.canceled
          ? const AuthFailure(AuthFailureKind.cancelled)
          : AuthFailure(AuthFailureKind.unknown, e.code.name);
    } on sb.AuthException catch (e) {
      throw mapAuthException(e);
    }
  }

  static String _nonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }
}
