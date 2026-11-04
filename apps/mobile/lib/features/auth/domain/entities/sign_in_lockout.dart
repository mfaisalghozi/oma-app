/// "3 wrong tries, then a 15-minute pause" (design v0.1, M04).
///
/// Client-side only for now: Supabase has IP rate limits, not a per-account
/// lockout, and where to enforce it on the server is still open (SA-FE §16).
/// A client counter is bypassable, so treat this as UX, not security.
class SignInLockout {
  const SignInLockout({this.failures = 0, this.lockedUntil});

  static const maxFailures = 3;
  static const pause = Duration(minutes: 15);

  final int failures;
  final DateTime? lockedUntil;

  int get triesLeft => (maxFailures - failures).clamp(0, maxFailures);

  bool isLocked(DateTime now) =>
      lockedUntil != null && now.isBefore(lockedUntil!);

  SignInLockout recordFailure(DateTime now) {
    final next = failures + 1;
    return next >= maxFailures
        ? SignInLockout(failures: next, lockedUntil: now.add(pause))
        : SignInLockout(failures: next);
  }

  /// After the pause ends the counter starts again.
  SignInLockout refresh(DateTime now) =>
      lockedUntil != null && !isLocked(now) ? const SignInLockout() : this;
}
