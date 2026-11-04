sealed class Failure implements Exception {
  const Failure(this.message);

  /// Developer-facing message. Never shown as-is to the user and never holds
  /// profile field values (sensitive under UU PDP).
  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'network']);
}

final class ApiFailure extends Failure {
  const ApiFailure({
    required this.code,
    required this.statusCode,
    String message = '',
    this.details = const [],
  }) : super(message);

  final String code;
  final int? statusCode;
  final List<Object?> details;

  List<FieldError> get fieldErrors => [
    for (final d in details)
      if (d is Map && d['field'] is String)
        FieldError(field: d['field'] as String, reason: '${d['reason'] ?? ''}'),
  ];

  @override
  String toString() => 'ApiFailure($statusCode $code)';
}

final class AuthFailure extends Failure {
  const AuthFailure(this.kind, [super.message = '']);

  final AuthFailureKind kind;

  @override
  String toString() => 'AuthFailure($kind)';
}

enum AuthFailureKind {
  cancelled,
  invalidCredentials,
  emailNotConfirmed,
  weakPassword,
  rateLimited,
  network,
  unknown,
}

final class DeviceFailure extends Failure {
  const DeviceFailure(super.message);
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure([super.message = 'unexpected']);
}

class FieldError {
  const FieldError({required this.field, required this.reason});

  final String field;
  final String reason;
}

abstract final class ApiErrorCode {
  static const unauthorized = 'UNAUTHORIZED';
  static const accountNotInitialized = 'ACCOUNT_NOT_INITIALIZED';
  static const accountFrozen = 'ACCOUNT_FROZEN';
  static const accountSuspended = 'ACCOUNT_SUSPENDED';
  static const consentRequired = 'CONSENT_REQUIRED';
  static const userUnder18 = 'USER_UNDER_18';
  static const invalidProfileData = 'INVALID_PROFILE_DATA';
  static const onboardingValidationFailed = 'ONBOARDING_VALIDATION_FAILED';
  static const onboardingAlreadyCompleted = 'ONBOARDING_ALREADY_COMPLETED';
  static const photoLimitExceeded = 'PHOTO_LIMIT_EXCEEDED';
  static const photoNotFound = 'PHOTO_NOT_FOUND';
  static const photoUploadIncomplete = 'PHOTO_UPLOAD_INCOMPLETE';
  static const invalidCoordinates = 'INVALID_COORDINATES';
  static const invalidMasterDataType = 'INVALID_MASTER_DATA_TYPE';
  static const masterDataNotFound = 'MASTER_DATA_NOT_FOUND';
  static const rateLimitExceeded = 'RATE_LIMIT_EXCEEDED';
  static const internalServerError = 'INTERNAL_SERVER_ERROR';

  static const unknown = 'UNKNOWN';
}
