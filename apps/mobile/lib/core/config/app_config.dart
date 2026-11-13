import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    this.nsfwScanBypass = false,
  });

  factory AppConfig.fromEnvironment() {
    final config = const AppConfig(
      flavor: String.fromEnvironment('FLAVOR', defaultValue: 'dev'),
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey: String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
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
      nsfwScanBypass: bool.fromEnvironment('NSFW_SCAN_BYPASS'),
    );
    config.validate();
    return config;
  }

  static const _threshold = String.fromEnvironment(
    'NSFW_THRESHOLD',
    defaultValue: '0.7',
  );

  final String flavor;
  final String supabaseUrl;
  final String supabasePublishableKey;

  final String apiBaseUrl;

  final String authRedirectUrl;

  /// Off until an SMS provider is chosen.
  final bool authPhoneEnabled;

  final String googleWebClientId;
  final String googleIosClientId;

  /// TODO(web): confirm the domain; `oma.app` is a placeholder.
  final String webBaseUrl;

  final NsfwModelSource nsfwModel;

  /// Dev-only escape hatch for flow regression while the model mirror is not
  /// hosted yet. Never valid outside the dev flavor; see [validate].
  final bool nsfwScanBypass;

  /// Fails loudly at startup instead of silently shipping a moderation bypass.
  void validate() {
    if (nsfwScanBypass && flavor != 'dev') {
      throw StateError(
        'NSFW_SCAN_BYPASS=true is only allowed with FLAVOR=dev, got "$flavor". '
        'Photo moderation cannot be disabled outside dev.',
      );
    }
  }

  Uri get termsUrl => Uri.parse('$webBaseUrl/terms');
  Uri get privacyUrl => Uri.parse('$webBaseUrl/privacy');

  bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}

final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);

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

  /// A string because `double.fromEnvironment` doesn't exist.
  final String threshold;

  double get thresholdValue => double.tryParse(threshold) ?? 0.7;
}
