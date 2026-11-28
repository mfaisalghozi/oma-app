/// Whether this install has already launched once.
abstract interface class InstallFlagStore {
  Future<bool> isInstalled();

  Future<void> markInstalled();
}

/// The secure store, narrowed to the one operation the guard needs.
abstract interface class SecureKeyValueStore {
  Future<void> deleteAll();
}

/// iOS keeps Keychain items when the app is deleted, so a reinstall can inherit
/// the previous owner's session, onboarding draft and swipe outbox. The install
/// flag lives in NSUserDefaults, which iOS does delete, so a missing flag means
/// "fresh install" and the secure store is wiped before anything reads it.
class FirstLaunchGuard {
  const FirstLaunchGuard({required this.flags, required this.secure});

  final InstallFlagStore flags;
  final SecureKeyValueStore secure;

  /// True when it wiped. Runs before the session restore, never after.
  Future<bool> ensureCleanInstall() async {
    if (await flags.isInstalled()) return false;
    await secure.deleteAll();
    await flags.markInstalled();
    return true;
  }
}
