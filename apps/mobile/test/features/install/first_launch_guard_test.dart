import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/features/install/domain/first_launch_guard.dart';

class _Flags implements InstallFlagStore {
  _Flags({this.installed = false});

  bool installed;
  int marks = 0;

  @override
  Future<bool> isInstalled() async => installed;

  @override
  Future<void> markInstalled() async {
    marks++;
    installed = true;
  }
}

class _Secure implements SecureKeyValueStore {
  int wipes = 0;

  @override
  Future<void> deleteAll() async => wipes++;
}

void main() {
  test('a missing flag wipes secure storage and sets the flag', () async {
    final flags = _Flags();
    final secure = _Secure();

    final wiped = await FirstLaunchGuard(
      flags: flags,
      secure: secure,
    ).ensureCleanInstall();

    expect(wiped, isTrue);
    expect(secure.wipes, 1);
    expect(flags.marks, 1);
    expect(flags.installed, isTrue);
  });

  test('an existing flag leaves the session and the draft alone', () async {
    final flags = _Flags(installed: true);
    final secure = _Secure();

    final wiped = await FirstLaunchGuard(
      flags: flags,
      secure: secure,
    ).ensureCleanInstall();

    expect(wiped, isFalse);
    expect(secure.wipes, 0);
    expect(flags.marks, 0);
  });

  test('a second call after a wipe is a no-op', () async {
    final flags = _Flags();
    final secure = _Secure();
    final guard = FirstLaunchGuard(flags: flags, secure: secure);

    await guard.ensureCleanInstall();
    await guard.ensureCleanInstall();

    expect(secure.wipes, 1);
  });
}
