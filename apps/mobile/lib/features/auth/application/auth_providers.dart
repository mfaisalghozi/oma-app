import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import '../data/api_account_repository.dart';
import '../data/native_social_auth_repository.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/social_auth_repository.dart';

/// The only place the auth interfaces are bound to implementations.
/// Tests override these providers with fakes.
final supabaseAuthRepositoryProvider = Provider<SupabaseAuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client.auth),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ref.watch(supabaseAuthRepositoryProvider),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => ApiAccountRepository(ref.watch(apiClientProvider)),
);

final socialAuthRepositoryProvider = Provider<SocialAuthRepository>(
  (ref) => NativeSocialAuthRepository(
    Supabase.instance.client.auth,
    ref.watch(appConfigProvider),
  ),
);

/// Email address of a sign-up waiting for its confirmation link (M04c), or
/// null. Set by the email flow; read by the gates.
final pendingEmailConfirmationProvider =
    NotifierProvider<PendingEmailConfirmation, String?>(
      PendingEmailConfirmation.new,
    );

class PendingEmailConfirmation extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? email) => state = email;
}
