import '../entities/account_state.dart';

abstract interface class AccountRepository {
  /// `POST /v1/me/initialize`: creates the account on first call and returns
  /// its status. Idempotent, so it is safe to call after every sign-in, on
  /// cold start and on resume.
  Future<AccountState> initialize();
}
