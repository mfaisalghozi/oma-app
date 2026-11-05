import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/api_device_repository.dart';
import '../data/device_adapters.dart';
import '../domain/device_repository.dart';
import '../domain/location_service.dart';
import '../domain/push_service.dart';

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);

final pushServiceProvider = Provider<PushService>(
  (ref) => FirebasePushService(),
);

final devicePlatformProvider = Provider<DevicePlatform>(
  (ref) => currentPlatform(),
);

final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => ApiDeviceRepository(ref.watch(apiClientProvider)),
);

final pushPendingFlagProvider = Provider<PendingFlag>(
  (ref) => PrefsPendingFlag(),
);

/// Never blocks onboarding: a failure sets a flag and [retryPending] retries.
class DeviceRegistrar {
  DeviceRegistrar(this._push, this._devices, this._pending, this._platform);

  final PushService _push;
  final DeviceRepository _devices;
  final PendingFlag _pending;
  final DevicePlatform _platform;

  Future<void> register() async {
    try {
      final token = await _push.token();
      if (token == null) {
        // Push isn't configured on this build: keep owing a registration.
        await _owe();
        return;
      }
      await _devices.registerPushToken(token: token, platform: _platform);
      await _pending.set(false);
    } on Object {
      await _owe();
    }
  }

  Future<void> retryPending() async {
    try {
      if (await _pending.get()) await register();
    } on Object {
      // Try again on the next start.
    }
  }

  Future<void> _owe() async {
    try {
      await _pending.set(true);
    } on Object {
      // Storage failed too; nothing more to do.
    }
  }
}

final deviceRegistrarProvider = Provider<DeviceRegistrar>(
  (ref) => DeviceRegistrar(
    ref.watch(pushServiceProvider),
    ref.watch(deviceRepositoryProvider),
    ref.watch(pushPendingFlagProvider),
    ref.watch(devicePlatformProvider),
  ),
);
