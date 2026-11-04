import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../data/device_adapters.dart';
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

abstract interface class PendingFlag {
  Future<bool> get();
  Future<void> set(bool value);
}

class PrefsPendingFlag implements PendingFlag {
  static const _key = 'oma.push.registration_pending';
  final _prefs = SharedPreferencesAsync();

  @override
  Future<bool> get() async => await _prefs.getBool(_key) ?? false;

  @override
  Future<void> set(bool value) => _prefs.setBool(_key, value);
}

final pushPendingFlagProvider = Provider<PendingFlag>(
  (ref) => PrefsPendingFlag(),
);

/// Never blocks onboarding: a failure sets a flag and [retryPending] retries.
class DeviceRegistrar {
  DeviceRegistrar(this._ref);

  final Ref _ref;

  Future<void> register() async {
    final flag = _ref.read(pushPendingFlagProvider);
    Future<void> owe() async {
      try {
        await flag.set(true);
      } on Object {
        // Storage failed too; nothing more to do.
      }
    }

    try {
      final token = await _ref.read(pushServiceProvider).token();
      if (token == null) {
        // Push isn't configured on this build: keep owing a registration.
        await owe();
        return;
      }
      await _ref
          .read(apiClientProvider)
          .post(
            '/devices',
            body: {
              'token': token,
              'platform': _ref.read(devicePlatformProvider).name,
              'provider': 'fcm',
            },
          );
      await flag.set(false);
    } on Object {
      await owe();
    }
  }

  Future<void> retryPending() async {
    try {
      if (await _ref.read(pushPendingFlagProvider).get()) await register();
    } on Object {
      // Try again on the next start.
    }
  }
}

final deviceRegistrarProvider = Provider<DeviceRegistrar>(DeviceRegistrar.new);
