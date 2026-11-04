/// Supabase's password policy enforces the same on the server.
class PasswordRules {
  const PasswordRules(this.password);

  final String password;

  bool get longEnough => password.length >= 8;

  bool get hasLetterAndNumber =>
      RegExp(r'[A-Za-z]').hasMatch(password) &&
      RegExp(r'[0-9]').hasMatch(password);

  bool get valid => longEnough && hasLetterAndNumber;
}

bool looksLikeEmail(String email) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
