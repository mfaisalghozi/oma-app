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

  Uri get termsUrl => Uri.parse('$webBaseUrl/terms');
  Uri get privacyUrl => Uri.parse('$webBaseUrl/privacy');

  bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}

final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);
