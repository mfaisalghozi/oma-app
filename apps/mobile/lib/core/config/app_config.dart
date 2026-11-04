import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Build-time configuration, passed with
/// `flutter run --dart-define-from-file=config/dev.json`.
///
/// Feature flags (such as `AUTH_PHONE_ENABLED`) live here until Online config
/// (P2) exists, so a switch is per release, not per user.
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.apiBaseUrl,
    required this.authRedirectUrl,
    this.authPhoneEnabled = false,
    this.googleWebClientId = '',
    this.googleIosClientId = '',
    this.webBaseUrl = 'https://oma.app',
    this.nsfwModel = const NsfwModelSource(),
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    flavor: String.fromEnvironment('FLAVOR', defaultValue: 'dev'),
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    apiBaseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    ),
    authRedirectUrl: String.fromEnvironment(
      'AUTH_REDIRECT_URL',
      defaultValue: 'com.mfaisalghozi.omaapp://auth/callback',
    ),
    authPhoneEnabled: bool.fromEnvironment('AUTH_PHONE_ENABLED'),
    googleWebClientId: String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    googleIosClientId: String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    webBaseUrl: String.fromEnvironment(
      'WEB_BASE_URL',
      defaultValue: 'https://oma.app',
    ),
    nsfwModel: NsfwModelSource(
      androidUrl: String.fromEnvironment('NSFW_MODEL_URL_ANDROID'),
      androidSha256: String.fromEnvironment('NSFW_MODEL_SHA256_ANDROID'),
      iosUrl: String.fromEnvironment('NSFW_MODEL_URL_IOS'),
      iosSha256: String.fromEnvironment('NSFW_MODEL_SHA256_IOS'),
      threshold: _threshold,
    ),
  );

  static const _threshold = String.fromEnvironment(
    'NSFW_THRESHOLD',
    defaultValue: '0.7',
  );

  final String flavor;
  final String supabaseUrl;
  final String supabasePublishableKey;

  /// Go API base URL, without the `/v1` prefix.
  final String apiBaseUrl;

  /// Deep link Supabase sends confirmation and reset links to (M04c).
  final String authRedirectUrl;

  /// Shows "Continue with phone number" on M02. Off until an SMS provider is
  /// chosen (phone OTP is a cut candidate, E2-05).
  final bool authPhoneEnabled;

  final String googleWebClientId;
  final String googleIosClientId;

  /// Public web (W01 to W04). Terms and Privacy live at W03.
  /// TODO(web): confirm the domain; `oma.app` is a placeholder.
  final String webBaseUrl;

  /// On-device photo check model (ONB-FE-08), served from our own mirror.
  final NsfwModelSource nsfwModel;

  Uri get termsUrl => Uri.parse('$webBaseUrl/terms');
  Uri get privacyUrl => Uri.parse('$webBaseUrl/privacy');

  bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}

final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);

/// Where the on-device NSFW model comes from. One file per platform
/// (`.tflite` for Android, `.mlmodel` for iOS) on our own mirror, pinned by
/// SHA-256 so a swapped file is never loaded.
class NsfwModelSource {
  const NsfwModelSource({
    this.androidUrl = '',
    this.androidSha256 = '',
    this.iosUrl = '',
    this.iosSha256 = '',
    this.threshold = '0.7',
  });

  final String androidUrl;
  final String androidSha256;
  final String iosUrl;
  final String iosSha256;

  /// Confidence at or above which nudity blocks a photo. Kept as a string
  /// because `double.fromEnvironment` doesn't exist. Tune on the fixed test
  /// set (docs/nsfw-threshold.md) before changing.
  final String threshold;

  double get thresholdValue => double.tryParse(threshold) ?? 0.7;
}
