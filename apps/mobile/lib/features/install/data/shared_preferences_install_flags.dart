import 'package:shared_preferences/shared_preferences.dart';

import '../domain/first_launch_guard.dart';

/// `NSUserDefaults` on iOS, cleared by the system on uninstall.
class SharedPreferencesInstallFlags implements InstallFlagStore {
  const SharedPreferencesInstallFlags();

  static const key = 'oma.installed';

  @override
  Future<bool> isInstalled() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  @override
  Future<void> markInstalled() async {
    await (await SharedPreferences.getInstance()).setBool(key, true);
  }
}
