import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/errors/failure.dart';
import '../domain/location_service.dart';
import '../domain/push_service.dart';

class GeolocatorLocationService implements LocationService {
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
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return (
        latitude: roundCoordinate(p.latitude),
        longitude: roundCoordinate(p.longitude),
      );
    } on Exception {
      throw const DeviceFailure('location fix');
    }
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
