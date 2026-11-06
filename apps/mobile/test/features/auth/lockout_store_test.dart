import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/features/auth/data/lockout_store.dart';

void main() {
  group('LockoutStore.parseLockout', () {
    test('a missing blob is an empty lockout', () {
      final lockout = LockoutStore.parseLockout(null);
      expect(lockout?.failures, 0);
      expect(lockout?.lockedUntil, isNull);
    });

    test('a valid blob round-trips', () {
      final until = DateTime.utc(2026, 11, 6, 12, 30);
      final lockout = LockoutStore.parseLockout(
        '{"failures":3,"lockedUntil":"${until.toIso8601String()}"}',
      );
      expect(lockout?.failures, 3);
      expect(lockout?.lockedUntil, until);
    });

    test('a truncated blob is unreadable instead of throwing', () {
      // Sign-in read this before the try in the controller, so a throw here
      // bricked every later attempt for the address.
      expect(LockoutStore.parseLockout('{"failures":'), isNull);
    });

    test('an older schema with the wrong types is unreadable', () {
      expect(LockoutStore.parseLockout('{"failures":"three"}'), isNull);
      expect(LockoutStore.parseLockout('[]'), isNull);
      expect(LockoutStore.parseLockout('null'), isNull);
    });
  });
}
