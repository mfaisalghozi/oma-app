/// Push permission and token for M11.
abstract interface class PushService {
  /// Shows the OS dialog. True when notifications are allowed.
  Future<bool> requestPermission();

  /// Current FCM token, or null when push isn't set up on this build.
  Future<String?> token();
}

/// `POST /v1/devices` body values (BE doc §8.2).
enum DevicePlatform { ios, android }
