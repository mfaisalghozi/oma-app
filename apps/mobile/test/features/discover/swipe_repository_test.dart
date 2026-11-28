import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/api/api_client.dart';
import 'package:oma_app/features/discover/data/api_swipe_repository.dart';
import 'package:oma_app/features/discover/domain/entities/swipe_command.dart';
import 'package:oma_app/features/discover/domain/entities/swipe_kind.dart';

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

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository(testUser));

  ApiSwipeRepository repository(_Adapter adapter) {
    final dio = buildApiDio(config: testConfig, tokens: auth)
      ..httpClientAdapter = adapter;
    return ApiSwipeRepository(ApiClient(dio));
  }

  final command = SwipeCommand(
    candidateId: 'cand-1',
    kind: SwipeKind.like,
    contextKind: 'regular_deck',
    contextId: 'ctx-1',
    idempotencyKey: 'key-1',
    createdAt: DateTime.utc(2026, 11, 27),
  );

  test('posts the decision with the context and the idempotency key', () async {
    final adapter = _Adapter(
      200,
      '{"data":{"action_id":"a1","action":"like","match":null}}',
    );
    final result = await repository(adapter).submit(command);

    expect(result.action, 'like');
    expect(result.match, isNull);
    final request = adapter.requests.single;
    expect(request.uri.path, '/v1/discovery/actions');
    expect(request.headers['Idempotency-Key'], 'key-1');
    expect(request.data, {
      'candidate_id': 'cand-1',
      'kind': 'like',
      'context': {'kind': 'regular_deck', 'id': 'ctx-1'},
    });
  });

  test('parses a match when the pair completed', () async {
    final adapter = _Adapter(
      200,
      '{"data":{"action_id":"a1","action":"like","match":'
      '{"id":"m1","conversation_status":"pending","conversation_id":null}}}',
    );
    final result = await repository(adapter).submit(command);
    expect(result.match?.id, 'm1');
    expect(result.match?.conversationStatus, 'pending');
  });
}
