import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../domain/device_repository.dart';
import '../domain/push_service.dart';

class ApiDeviceRepository implements DeviceRepository {
  ApiDeviceRepository(this._api);

  final ApiClient _api;

  @override
  Future<void> registerPushToken({
    required String token,
    required DevicePlatform platform,
  }) => _api.post(
    '/devices',
    body: {'token': token, 'platform': platform.name, 'provider': 'fcm'},
  );
}

class PrefsPendingFlag implements PendingFlag {
  static const _key = 'oma.push.registration_pending';
  final _prefs = SharedPreferencesAsync();

  @override
  Future<bool> get() async => await _prefs.getBool(_key) ?? false;

  @override
  Future<void> set(bool value) => _prefs.setBool(_key, value);
}
