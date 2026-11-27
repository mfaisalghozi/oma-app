import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/features/usage/domain/entities/daily_usage.dart';

void main() {
  Map<String, dynamic> payload() => {
    'bucket': '2026-11-12',
    'resets_at': '2026-11-12T17:00:00Z',
    'pro': false,
    'profile_complete': true,
    'likes': {'limit': 30, 'used': 18, 'reserved': 0, 'available': 12},
    'searches': {'limit': 3, 'used': 0, 'reserved': 0, 'available': 3},
  };

  test('parses the usage envelope', () {
    final usage = DailyUsage.fromJson(payload());
    expect(usage.likes.limit, 30);
    expect(usage.likes.available, 12);
    expect(usage.searches.limit, 3);
    expect(usage.profileComplete, isTrue);
    expect(usage.resetsAt.toUtc(), DateTime.utc(2026, 11, 12, 17));
  });

  test('spending a like moves available to used and stops at zero', () {
    const balance = UsageBalance(limit: 2, used: 1, reserved: 0, available: 1);
    final spent = balance.spend();
    expect(spent.available, 0);
    expect(spent.used, 2);
    expect(spent.spend().available, 0, reason: 'never goes negative');
  });

  test('an exhausted balance is reported as exhausted', () {
    expect(
      const UsageBalance(
        limit: 3,
        used: 3,
        reserved: 0,
        available: 0,
      ).isExhausted,
      isTrue,
    );
    expect(
      const UsageBalance(
        limit: 3,
        used: 2,
        reserved: 0,
        available: 1,
      ).isExhausted,
      isFalse,
    );
  });
}
