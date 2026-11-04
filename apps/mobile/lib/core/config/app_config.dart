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

  final String apiBaseUrl;

  final String authRedirectUrl;

  /// Off until an SMS provider is chosen.
  final bool authPhoneEnabled;

  final String googleWebClientId;
  final String googleIosClientId;

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
