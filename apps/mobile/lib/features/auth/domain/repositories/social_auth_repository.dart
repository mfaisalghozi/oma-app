import '../../../../core/errors/failure.dart';

abstract interface class SocialAuthRepository {
  Future<void> signInWithGoogle();

  Future<void> signInWithApple();

  /// Required on iOS once Google is offered.
  bool get appleAvailable;
}
