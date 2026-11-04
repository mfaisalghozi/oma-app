/// Account status from `POST /v1/me/initialize` (BE doc section 8.2).
enum AccountStatus {
  active,
  frozen,
  suspended;

  static AccountStatus parse(String? value) => switch (value) {
    'frozen' => AccountStatus.frozen,
    'suspended' => AccountStatus.suspended,
    _ => AccountStatus.active,
  };
}

/// What the backend says the user must do next.
enum NextAction {
  acceptConsents('accept_consents'),
  completeOnboarding('complete_onboarding'),
  discovery('discovery'),
  accountRestricted('account_restricted');

  const NextAction(this.wire);

  final String wire;

  static NextAction parse(String? value) => NextAction.values.firstWhere(
    (a) => a.wire == value,
    // Unknown values from a newer backend: send the user through onboarding,
    // where the API will reject anything that is not allowed yet.
    orElse: () => NextAction.completeOnboarding,
  );
}

class AccountState {
  const AccountState({
    required this.userId,
    required this.status,
    required this.onboardingCompleted,
    required this.nextAction,
    this.accountCreated = false,
    this.suspendedUntil,
  });

  factory AccountState.fromJson(Map<String, Object?> json) => AccountState(
    userId: json['user_id']! as String,
    status: AccountStatus.parse(json['account_status'] as String?),
    accountCreated: json['account_created'] == true,
    onboardingCompleted: json['onboarding_completed'] == true,
    nextAction: NextAction.parse(json['next_action'] as String?),
    suspendedUntil: DateTime.tryParse('${json['suspended_until'] ?? ''}'),
  );

  final String userId;
  final AccountStatus status;
  final bool accountCreated;
  final bool onboardingCompleted;
  final NextAction nextAction;
  final DateTime? suspendedUntil;

  bool get isRestricted =>
      status != AccountStatus.active ||
      nextAction == NextAction.accountRestricted;
}
