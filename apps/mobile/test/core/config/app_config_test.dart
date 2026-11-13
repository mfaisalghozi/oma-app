import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/config/app_config.dart';
import 'package:oma_app/features/photos/application/photo_scanner_provider.dart';
import 'package:oma_app/features/photos/data/bypass_photo_scanner.dart';
import 'package:oma_app/features/photos/data/nsfw_detect_photo_scanner.dart';

AppConfig _config({required String flavor, required bool bypass}) => AppConfig(
  flavor: flavor,
  supabaseUrl: 'https://example.supabase.co',
  supabasePublishableKey: 'key',
  apiBaseUrl: 'http://10.0.2.2:8080',
  authRedirectUrl: 'com.mfaisalghozi.omaapp://auth/callback',
  nsfwScanBypass: bypass,
);

void main() {
  group('NSFW scan bypass guard', () {
    test('is accepted in the dev flavor', () {
      expect(
        () => _config(flavor: 'dev', bypass: true).validate(),
        returnsNormally,
      );
    });

    test('throws in the release flavor', () {
      expect(
        () => _config(flavor: 'release', bypass: true).validate(),
        throwsStateError,
      );
    });

    test('throws in the staging flavor', () {
      expect(
        () => _config(flavor: 'staging', bypass: true).validate(),
        throwsStateError,
      );
    });

    test('is inert when the flag is off', () {
      for (final flavor in ['dev', 'staging', 'release']) {
        expect(
          () => _config(flavor: flavor, bypass: false).validate(),
          returnsNormally,
          reason: 'flavor $flavor must not require the bypass',
        );
      }
    });
  });

  group('photoScannerProvider', () {
    test('returns the bypass scanner when the flag is on', () {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            _config(flavor: 'dev', bypass: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(photoScannerProvider), isA<BypassPhotoScanner>());
    });

    test('returns the real scanner when the flag is off', () {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            _config(flavor: 'dev', bypass: false),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(photoScannerProvider),
        isA<NsfwDetectPhotoScanner>(),
      );
    });
  });
}
