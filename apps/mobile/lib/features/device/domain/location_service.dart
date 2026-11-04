enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// Coordinates already rounded on the device.
typedef RoundedFix = ({double latitude, double longitude});

/// Device location for M10: one coarse fix, no tracking.
abstract interface class LocationService {
  Future<LocationAccess> status();

  /// Shows the OS dialog when it can still be shown.
  Future<LocationAccess> request();

  /// One coarse fix, rounded with [roundCoordinate] before it is returned.
  Future<RoundedFix> currentFix();

  Future<void> openSettings();
}

/// Rounds to 0.01° (about 1.1 km), so the exact spot never leaves the
/// phone and distance can only be shown to the nearest km.
double roundCoordinate(double v) => (v * 100).roundToDouble() / 100;
