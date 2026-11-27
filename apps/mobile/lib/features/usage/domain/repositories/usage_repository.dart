import '../entities/daily_usage.dart';

abstract interface class UsageRepository {
  Future<DailyUsage> fetch();
}
