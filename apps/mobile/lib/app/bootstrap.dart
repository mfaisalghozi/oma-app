import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api/api_client.dart';
import '../core/config/app_config.dart';
import '../core/storage/secure_session_storage.dart';
import '../features/auth/application/auth_providers.dart';
import 'app.dart';

/// Initialises SDKs, binds providers and runs the app.
///
/// Firebase (push, Crashlytics) joins here once the Firebase projects exist.
Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!config.hasSupabase) {
    throw StateError(
      'Supabase is not configured. Run with '
      '--dart-define-from-file=config/dev.json (see config/dev.example.json).',
    );
  }

  await Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      localStorage: SecureSessionStorage(),
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        accessTokenSourceProvider.overrideWith(
          (ref) => ref.watch(supabaseAuthRepositoryProvider),
        ),
      ],
      child: const OmaApp(),
    ),
  );
}
