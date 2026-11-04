import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/api/api_client.dart';
import 'package:oma_app/core/errors/failure.dart';

import '../../helpers/fakes.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.responses);

  final List<(int, String)> responses;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = responses.removeAt(0);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeAuthRepository auth;

  ApiClient client(_Adapter adapter) {
    final dio = buildApiDio(config: testConfig, tokens: auth)
      ..httpClientAdapter = adapter;
    return ApiClient(dio);
  }

  setUp(() => auth = FakeAuthRepository(testUser));

  test('unwraps the data envelope and sends the bearer token', () async {
    final adapter = _Adapter([(200, '{"data":{"ok":true}}')]);
    final data = await client(adapter).post('/me/initialize');
    expect(data, {'ok': true});
    expect(adapter.requests.single.headers['Authorization'], 'Bearer token');
    expect(adapter.requests.single.uri.path, '/v1/me/initialize');
  });

  test('every POST gets an Idempotency-Key, a given key is kept', () async {
    final adapter = _Adapter([(200, '{"data":1}'), (200, '{"data":1}')]);
    final api = client(adapter);
    await api.post('/a');
    await api.post('/b', idempotencyKey: 'fixed');
    expect(adapter.requests[0].headers['Idempotency-Key'], isNotEmpty);
    expect(adapter.requests[1].headers['Idempotency-Key'], 'fixed');
  });

  test('maps the error envelope to ApiFailure with field errors', () async {
    final adapter = _Adapter([
      (
        422,
        '{"error":{"code":"ONBOARDING_VALIDATION_FAILED","message":"x",'
            '"details":[{"field":"birthdate","reason":"USER_UNDER_18"}]}}',
      ),
    ]);
    await expectLater(
      client(adapter).post('/me/onboarding'),
      throwsA(
        isA<ApiFailure>()
            .having(
              (f) => f.code,
              'code',
              ApiErrorCode.onboardingValidationFailed,
            )
            .having((f) => f.statusCode, 'status', 422)
            .having((f) => f.fieldErrors.single.field, 'field', 'birthdate'),
      ),
    );
  });

  test('401 refreshes once and retries', () async {
    final adapter = _Adapter([(401, '{}'), (200, '{"data":"ok"}')]);
    expect(await client(adapter).get('/me/consents'), 'ok');
    expect(adapter.requests, hasLength(2));
    expect(auth.signOutCalls, 0);
  });

  test('401 after the retry signs the user out', () async {
    final adapter = _Adapter([(401, '{}'), (401, '{}')]);
    await expectLater(
      client(adapter).get('/me/consents'),
      throwsA(isA<ApiFailure>().having((f) => f.statusCode, 'status', 401)),
    );
    expect(auth.signOutCalls, 1);
  });

  test('connection errors become NetworkFailure', () {
    final failure = mapDioException(
      DioException.connectionError(
        requestOptions: RequestOptions(),
        reason: 'offline',
      ),
    );
    expect(failure, isA<NetworkFailure>());
  });
}
