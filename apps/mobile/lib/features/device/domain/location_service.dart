enum LocationAccess { granted, denied, deniedForever, serviceOff }

typedef RoundedFix = ({double latitude, double longitude});

abstract interface class LocationService {
  Future<LocationAccess> status();

  Future<LocationAccess> request();

  Future<RoundedFix> currentFix();

  Future<void> openSettings();
}

/// Rounds to 0.01° (about 1.1 km), so the exact spot never leaves the
/// phone and distance can only be shown to the nearest km.
double roundCoordinate(double v) => (v * 100).roundToDouble() / 100;
