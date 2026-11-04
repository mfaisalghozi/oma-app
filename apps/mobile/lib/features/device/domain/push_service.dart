abstract interface class PushService {
  Future<bool> requestPermission();

  /// Null when push isn't set up on this build.
  Future<String?> token();
}

enum DevicePlatform { ios, android }
