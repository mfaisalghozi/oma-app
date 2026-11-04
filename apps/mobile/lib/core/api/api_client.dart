import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../errors/failure.dart';

/// Supplies and refreshes the Supabase access token for API calls.
///
/// Implemented by the auth feature; kept as a small interface here so `core`
/// does not depend on a feature.
abstract interface class AccessTokenSource {
  Future<String?> accessToken();

  /// Refreshes the session once. Returns false when the session is gone.
  Future<bool> refresh();

  /// Called when a refreshed token is still rejected: ends the session so the
  /// gates send the user back to sign-in.
  Future<void> onUnauthorized();
}

final accessTokenSourceProvider = Provider<AccessTokenSource>(
  (ref) => throw UnimplementedError('accessTokenSourceProvider not bound'),
);

/// Called when any endpoint answers `CONSENT_REQUIRED` (for example after the
/// Terms change). The app binds it to a session refresh, so the gates send
/// the user back to M05 from wherever they are.
final consentRequiredHandlerProvider = Provider<Future<void> Function()>(
  (ref) => () async {},
);

/// Thin wrapper over Dio for the Go API (`/v1`).
///
/// It unwraps the `{"data": ...}` envelope and turns every error into a
/// [Failure]. When the Go service publishes the onboarding endpoints in
/// `libs/contracts/openapi.yaml`, the generated dart-dio client replaces the
/// hand-written calls in each feature's data layer; this class keeps the
/// interceptors.
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Dio get dio => _dio;

  Future<Object?> get(String path, {Map<String, Object?>? query}) =>
      _send(() => _dio.get<Object?>(path, queryParameters: query));

  Future<Object?> post(String path, {Object? body, String? idempotencyKey}) =>
      _send(
        () => _dio.post<Object?>(
          path,
          data: body,
          options: _idempotent(idempotencyKey),
        ),
      );

  Future<Object?> put(String path, {Object? body}) =>
      _send(() => _dio.put<Object?>(path, data: body));

  Future<Object?> patch(String path, {Object? body}) =>
      _send(() => _dio.patch<Object?>(path, data: body));

  Future<Object?> delete(String path) =>
      _send(() => _dio.delete<Object?>(path));

  Options? _idempotent(String? key) => key == null
      ? null
      : Options(headers: {IdempotencyInterceptor.header: key});

  Future<Object?> _send(Future<Response<Object?>> Function() call) async {
    try {
      final res = await call();
      final body = res.data;
      if (body is Map && body.containsKey('data')) return body['data'];
      return body;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

/// Maps a Dio error to the app's [Failure] types.
Failure mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.sendTimeout:
      return const NetworkFailure();
    case DioExceptionType.transformTimeout:
      return const UnexpectedFailure('transform timeout');
    case DioExceptionType.badResponse:
      final res = e.response;
      final body = res?.data;
      final error = body is Map ? body['error'] : null;
      if (error is Map) {
        final details = error['details'];
        return ApiFailure(
          code: '${error['code'] ?? ApiErrorCode.unknown}',
          statusCode: res?.statusCode,
          message: '${error['message'] ?? ''}',
          details: details is List ? details.cast<Object?>() : const [],
        );
      }
      return ApiFailure(
        code: res?.statusCode == 401
            ? ApiErrorCode.unauthorized
            : ApiErrorCode.unknown,
        statusCode: res?.statusCode,
      );
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return e.error is Failure
          ? e.error! as Failure
          : UnexpectedFailure(e.type.name);
  }
}

/// Adds the Supabase access token, refreshes it once on 401 and retries.
/// A second 401 ends the session so the gates return the user to sign-in.
///
/// Concurrent 401s share one refresh. (Not a QueuedInterceptor: the retried
/// request re-enters this interceptor, which would deadlock a queue.)
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokens, this._dio);

  final AccessTokenSource _tokens;
  final Dio _dio;
  Future<bool>? _refreshing;
  static const _retried = 'oma_auth_retried';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokens.accessToken();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401) return handler.next(err);
    if (options.extra[_retried] == true) {
      await _tokens.onUnauthorized();
      return handler.next(err);
    }
    final refreshed = await (_refreshing ??= _tokens.refresh().whenComplete(
      () => _refreshing = null,
    ));
    if (!refreshed) {
      await _tokens.onUnauthorized();
      return handler.next(err);
    }
    options.extra[_retried] = true;
    try {
      handler.resolve(await _dio.fetch<Object?>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Fires [onConsentRequired] on a `CONSENT_REQUIRED` error, then passes the
/// error on unchanged so the caller still fails.
class ConsentRequiredInterceptor extends Interceptor {
  ConsentRequiredInterceptor(this.onConsentRequired);

  final Future<void> Function() onConsentRequired;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final body = err.response?.data;
    final error = body is Map ? body['error'] : null;
    if (error is Map && error['code'] == ApiErrorCode.consentRequired) {
      unawaited(onConsentRequired());
    }
    handler.next(err);
  }
}

/// Adds an `Idempotency-Key` to every POST so a retried like, message,
/// purchase or onboarding submit is never applied twice. Callers that retry a
/// specific operation pass their own stable key (see [ApiClient.post]).
class IdempotencyInterceptor extends Interceptor {
  IdempotencyInterceptor([Uuid? uuid]) : _uuid = uuid ?? const Uuid();

  static const header = 'Idempotency-Key';
  final Uuid _uuid;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method == 'POST' && !options.headers.containsKey(header)) {
      options.headers[header] = _uuid.v4();
    }
    handler.next(options);
  }
}

Dio buildApiDio({
  required AppConfig config,
  required AccessTokenSource tokens,
  Future<void> Function()? onConsentRequired,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: '${config.apiBaseUrl}/v1',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );
  dio.interceptors.addAll([
    AuthInterceptor(tokens, dio),
    IdempotencyInterceptor(),
    if (onConsentRequired != null)
      ConsentRequiredInterceptor(onConsentRequired),
  ]);
  return dio;
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final dio = buildApiDio(
    config: ref.watch(appConfigProvider),
    tokens: ref.watch(accessTokenSourceProvider),
    onConsentRequired: ref.watch(consentRequiredHandlerProvider),
  );
  ref.onDispose(dio.close);
  return ApiClient(dio);
});
