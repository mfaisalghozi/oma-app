import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api/api_client.dart';
import '../core/config/app_config.dart';
import '../core/storage/secure_session_storage.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/auth/application/session_controller.dart';
import '../features/install/data/flutter_secure_key_value_store.dart';
import '../features/install/data/shared_preferences_install_flags.dart';
import '../features/install/domain/first_launch_guard.dart';
import 'app.dart';

Future<void> bootstrap(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!config.hasSupabase) {
    throw StateError(
      'Supabase is not configured. Run with '
      '--dart-define-from-file=config/dev.json (see config/dev.example.json).',
    );
  }

  // Before Supabase reads the Keychain: a reinstall must not inherit the
  // previous owner's session, draft or outbox.
  await const FirstLaunchGuard(
    flags: SharedPreferencesInstallFlags(),
    secure: FlutterSecureKeyValueStore(),
  ).ensureCleanInstall();

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
        consentRequiredHandlerProvider.overrideWith(
          (ref) =>
              () => ref.read(sessionControllerProvider.notifier).refresh(),
        ),
      ],
      child: const OmaApp(),
    ),
  );
}
