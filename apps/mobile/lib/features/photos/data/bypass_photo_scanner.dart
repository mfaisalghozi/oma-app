import '../domain/photo_scanner.dart';

/// Dev-only scanner used while the on-device model mirror is not hosted yet.
///
/// It lets the onboarding flow be regressed end to end without downloading a
/// 4-5 MB model. It is only reachable when `NSFW_SCAN_BYPASS=true` **and**
/// `FLAVOR=dev`; [AppConfig.validate] throws for every other flavor.
///
/// This does not remove server-side moderation: the backend still reviews
/// uploaded photos, so a bypassed client cannot make content public on its own.
class BypassPhotoScanner implements PhotoScanner {
  const BypassPhotoScanner();

  @override
  Future<void> prepare() async {}

  @override
  Future<PhotoVerdict> scan(String filePath) async => const PhotoAllowed();
}
