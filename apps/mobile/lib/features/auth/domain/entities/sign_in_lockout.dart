/// Client-side only, so it is UX, not security: a client counter is bypassable.
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

  SignInLockout refresh(DateTime now) =>
      lockedUntil != null && !isLocked(now) ? const SignInLockout() : this;
}
