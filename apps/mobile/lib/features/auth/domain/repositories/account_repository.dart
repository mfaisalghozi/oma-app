import '../entities/account_state.dart';

abstract interface class AccountRepository {
  /// Idempotent: safe after every sign-in, cold start and resume.
  Future<AccountState> initialize();
}
