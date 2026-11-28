import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/api/api_client.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/discover/data/api_deck_repository.dart';

import '../../helpers/fakes.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body, [this.status = 200]);

  final String body;
  final int status;
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

const _pageBody =
    '{"data":{"context_id":"ctx","cards":[{"id":"c1","display_name":"Dimas",'
    '"age":28,"height_cm":178,"approx_distance_km":4,"bio":"x","ambition":null,'
    '"occupation":null,"education_degree":null,"profile_revision":1,'
    '"photos":[],"hobbies":[],"looking_for":[],"personality":null,'
    '"religion":null,"university":null}],"next_cursor":"cur",'
    '"deck_expires_at":"2026-11-27T18:00:00Z","end_reason":null}}';

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository(testUser));

  ApiDeckRepository repository(_Adapter adapter) {
    final dio = buildApiDio(config: testConfig, tokens: auth)
      ..httpClientAdapter = adapter;
    return ApiDeckRepository(ApiClient(dio));
  }

  test('sends X-Limit and no cursor on the first read', () async {
    final adapter = _Adapter(_pageBody);
    final page = await repository(adapter).fetch(limit: 20);

    expect(page.cards.single.displayName, 'Dimas');
    expect(page.nextCursor, 'cur');
    final request = adapter.requests.single;
    expect(request.uri.path, '/v1/discovery');
    expect(request.uri.queryParameters, isEmpty);
    expect(request.headers['X-Limit'], '20');
    expect(request.headers.containsKey('X-Cursor'), isFalse);
  });

  test('sends X-Cursor and never a query string', () async {
    final adapter = _Adapter(_pageBody);
    await repository(adapter).fetch(limit: 5, cursor: 'abc');

    final request = adapter.requests.single;
    expect(request.uri.queryParameters, isEmpty);
    expect(request.headers['X-Limit'], '5');
    expect(request.headers['X-Cursor'], 'abc');
  });

  test('maps a failure to a typed ApiFailure', () async {
    final adapter = _Adapter(
      '{"error":{"code":"STALE_DISCOVERY_CONTEXT","message":"stale"}}',
      409,
    );
    await expectLater(
      repository(adapter).fetch(cursor: 'abc'),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.code,
          'code',
          'STALE_DISCOVERY_CONTEXT',
        ),
      ),
    );
  });
}
