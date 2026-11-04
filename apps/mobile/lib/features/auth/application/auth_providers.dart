import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../data/api_account_repository.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/repositories/account_repository.dart';
import '../domain/repositories/auth_repository.dart';

final supabaseAuthRepositoryProvider = Provider<SupabaseAuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client.auth),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ref.watch(supabaseAuthRepositoryProvider),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => ApiAccountRepository(ref.watch(apiClientProvider)),
);

final pendingEmailConfirmationProvider =
    NotifierProvider<PendingEmailConfirmation, String?>(
      PendingEmailConfirmation.new,
    );

class PendingEmailConfirmation extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? email) => state = email;
}
