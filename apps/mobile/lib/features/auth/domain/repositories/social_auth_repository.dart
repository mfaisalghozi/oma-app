import '../../../../core/errors/failure.dart';

/// Native Google and Apple sign-in, handed to Supabase as ID tokens.
///
/// Throws [AuthFailure] with [AuthFailureKind.cancelled] when the user closes
/// the native sheet; the hub stays on M02 without a message.
abstract interface class SocialAuthRepository {
  Future<void> signInWithGoogle();

  Future<void> signInWithApple();

  /// Apple sign-in is offered on iOS (required there once Google is offered).
  bool get appleAvailable;
}
