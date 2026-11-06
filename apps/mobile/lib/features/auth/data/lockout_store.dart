import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/sign_in_lockout.dart';

/// Keyed by a hash so the address itself is not stored.
class LockoutStore {
  LockoutStore([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  String _key(String email) =>
      'oma.signin_lockout.${sha256.convert(utf8.encode(email.trim().toLowerCase()))}';

  Future<SignInLockout> read(String email) async {
    final key = _key(email);
    final raw = await _prefs.getString(key);
    final lockout = parseLockout(raw);
    if (lockout != null) return lockout;
    // A truncated or older-schema blob must not brick sign-in: drop it so the
    // next attempt starts from a clean lockout.
    await _prefs.remove(key);
    return const SignInLockout();
  }

  /// Null only when [raw] exists but cannot be read, so [read] can drop it.
  static SignInLockout? parseLockout(String? raw) {
    if (raw == null) return const SignInLockout();
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return SignInLockout(
        failures: json['failures'] as int? ?? 0,
        lockedUntil: DateTime.tryParse('${json['lockedUntil'] ?? ''}'),
      );
    } on Object {
      return null;
    }
  }

  Future<void> write(String email, SignInLockout lockout) => _prefs.setString(
    _key(email),
    jsonEncode({
      'failures': lockout.failures,
      'lockedUntil': lockout.lockedUntil?.toIso8601String(),
    }),
  );

  Future<void> clear(String email) => _prefs.remove(_key(email));
}
