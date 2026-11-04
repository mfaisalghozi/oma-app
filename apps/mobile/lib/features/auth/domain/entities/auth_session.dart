/// The signed-in Supabase user, as the app needs it. No tokens here: the
/// data layer keeps those.
class AuthSession {
  const AuthSession({
    required this.userId,
    this.email,
    this.emailConfirmed = true,
  });

  final String userId;
  final String? email;

  /// False while an email sign-up is waiting for its confirmation link (M04c).
  final bool emailConfirmed;

  @override
  bool operator ==(Object other) =>
      other is AuthSession &&
      other.userId == userId &&
      other.email == email &&
      other.emailConfirmed == emailConfirmed;

  @override
  int get hashCode => Object.hash(userId, email, emailConfirmed);
}
