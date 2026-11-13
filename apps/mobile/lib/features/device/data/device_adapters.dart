import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/errors/failure.dart';
import '../domain/location_service.dart';
import '../domain/push_service.dart';

class GeolocatorLocationService implements LocationService {
  static const _maxFixAge = Duration(minutes: 30);

  @override
  Future<LocationAccess> status() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    return _map(await Geolocator.checkPermission());
  }

  @override
  Future<LocationAccess> request() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    return _map(await Geolocator.requestPermission());
  }

  @override
  Future<RoundedFix> currentFix() async {
    Position fix;
    try {
      fix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // `low` asks the low-power provider, which has nothing to return on a
          // cold start, so the request sat until the time limit and then failed
          // even with permission granted and a GPS fix available.
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } on Exception {
      // A slightly stale fix still gives a usable distance, which beats
      // dropping the user into the city picker.
      final last = await Geolocator.getLastKnownPosition();
      if (last == null ||
          DateTime.now().difference(last.timestamp) > _maxFixAge) {
        throw const DeviceFailure('location fix');
      }
      fix = last;
    }
    return (
      latitude: roundCoordinate(fix.latitude),
      longitude: roundCoordinate(fix.longitude),
    );
  }

  @override
  Future<void> openSettings() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return;
    }
    await Geolocator.openAppSettings();
  }

  static LocationAccess _map(LocationPermission p) => switch (p) {
    LocationPermission.always ||
    LocationPermission.whileInUse => LocationAccess.granted,
    LocationPermission.deniedForever => LocationAccess.deniedForever,
    LocationPermission.denied ||
    LocationPermission.unableToDetermine => LocationAccess.denied,
  };
}

/// Without Firebase initialised it still asks permission but returns no token.
class FirebasePushService implements PushService {
  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  @override
  Future<bool> requestPermission() async {
    if (_firebaseReady) {
      final s = await FirebaseMessaging.instance.requestPermission();
      return s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
    }
    return (await Permission.notification.request()).isGranted;
  }

  /// Firebase Installation ID from `register()`; `getToken()` is deprecated.
  @override
  Future<String?> token() async {
    if (!_firebaseReady) return null;
    final messaging = FirebaseMessaging.instance;
    final id = messaging.onRegistered.first.timeout(
      const Duration(seconds: 20),
    );
    await messaging.register();
    return id;
  }
}

DevicePlatform currentPlatform() =>
    Platform.isIOS ? DevicePlatform.ios : DevicePlatform.android;
