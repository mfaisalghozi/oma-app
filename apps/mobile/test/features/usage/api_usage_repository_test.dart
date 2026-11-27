import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/api/api_client.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/usage/data/api_usage_repository.dart';

import '../../helpers/fakes.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);

  final int status;
  final String body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
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

const _usageBody =
    '{"data":{"bucket":"2026-11-12",'
    '"resets_at":"2026-11-12T17:00:00Z","pro":false,"profile_complete":true,'
    '"likes":{"limit":30,"used":18,"reserved":0,"available":12},'
    '"searches":{"limit":3,"used":0,"reserved":0,"available":3}}}';

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository(testUser));

  ApiUsageRepository repository(_Adapter adapter) {
    final dio = buildApiDio(config: testConfig, tokens: auth)
      ..httpClientAdapter = adapter;
    return ApiUsageRepository(ApiClient(dio));
  }

  test('reads GET /v1/me/usage without query parameters', () async {
    final adapter = _Adapter(200, _usageBody);
    final usage = await repository(adapter).fetch();
    expect(usage.likes.available, 12);
    expect(usage.searches.available, 3);
    expect(adapter.requests.single.uri.path, '/v1/me/usage');
    expect(adapter.requests.single.queryParameters, isEmpty);
  });

  test('maps a 403 gate error to a typed failure', () async {
    final adapter = _Adapter(
      403,
      '{"error":{"code":"DISCOVERY_NOT_ELIGIBLE","message":"not eligible"}}',
    );
    await expectLater(
      repository(adapter).fetch(),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          'DISCOVERY_NOT_ELIGIBLE',
        ),
      ),
    );
  });
}
