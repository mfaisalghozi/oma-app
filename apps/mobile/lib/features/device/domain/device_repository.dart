import 'push_service.dart';

abstract interface class DeviceRepository {
  Future<void> registerPushToken({
    required String token,
    required DevicePlatform platform,
  });
}

/// A push registration still owed, kept across launches.
abstract interface class PendingFlag {
  Future<bool> get();
  Future<void> set(bool value);
}
