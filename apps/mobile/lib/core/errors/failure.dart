/// Errors the app switches on. Screens never see HTTP codes or Dio types;
/// they get a [Failure] and switch on its type or [ApiFailure.code].
sealed class Failure implements Exception {
  const Failure(this.message);

  /// Developer-facing message. Never shown as-is to the user and never holds
  /// profile field values (sensitive under UU PDP).
  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

/// No connection, DNS failure or timeout. The UI shows the offline pattern.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'network']);
}

/// The Go API answered with the standard error envelope
/// `{"error": {"code", "message", "details"}}` (BE doc section 8.1).
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

  /// `details` entries shaped `{field, reason}` (422 validation errors).
  List<FieldError> get fieldErrors => [
    for (final d in details)
      if (d is Map && d['field'] is String)
        FieldError(field: d['field'] as String, reason: '${d['reason'] ?? ''}'),
  ];

  @override
  String toString() => 'ApiFailure($statusCode $code)';
}

/// Sign-in or sign-up failure from Supabase Auth, mapped to a stable [kind].
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

/// A device capability failed (permission, model download, picker).
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

/// Error codes from the BE Technical Doc section 9.
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

  /// Used when a response had no parsable error envelope.
  static const unknown = 'UNKNOWN';
}
