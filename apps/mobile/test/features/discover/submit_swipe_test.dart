import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/discover/domain/entities/swipe_command.dart';
import 'package:oma_app/features/discover/domain/entities/swipe_kind.dart';
import 'package:oma_app/features/discover/domain/usecases/submit_swipe.dart';

import '../../helpers/deck_fakes.dart';

SwipeCommand command([String key = 'k1']) => SwipeCommand(
  candidateId: 'c1',
  kind: SwipeKind.like,
  contextKind: 'regular_deck',
  contextId: 'ctx',
  idempotencyKey: key,
  createdAt: DateTime.utc(2026, 11, 27),
);

void main() {
  late FakeSwipeRepository repository;
  late MemorySwipeOutbox outbox;

  setUp(() {
    repository = FakeSwipeRepository();
    outbox = MemorySwipeOutbox();
  });

  Future<SwipeOutcome> send([SwipeCommand? cmd]) =>
      SubmitSwipe(repository, outbox)(cmd ?? command());

  test('accepted when the server takes it', () async {
    expect(await send(), SwipeOutcome.accepted);
    expect(outbox.saved, isEmpty);
  });

  test('queues on a network failure', () async {
    repository.error = const NetworkFailure();
    expect(await send(), SwipeOutcome.queued);
    expect(outbox.saved.single.idempotencyKey, 'k1');
  });

  test('queues on a 5xx', () async {
    repository.error = const ApiFailure(
      code: ApiErrorCode.internalServerError,
      statusCode: 500,
    );
    expect(await send(), SwipeOutcome.queued);
    expect(outbox.saved, hasLength(1));
  });

  test('reports a spent like quota without queueing', () async {
    repository.error = const ApiFailure(
      code: ApiErrorCode.likeLimitReached,
      statusCode: 429,
    );
    expect(await send(), SwipeOutcome.likeLimit);
    expect(outbox.saved, isEmpty);
  });

  test('reports an empty super-like balance without queueing', () async {
    repository.error = const ApiFailure(
      code: ApiErrorCode.superLikeBalanceEmpty,
      statusCode: 429,
    );
    expect(await send(), SwipeOutcome.superLikeEmpty);
    expect(outbox.saved, isEmpty);
  });

  test('drops a stale context', () async {
    repository.error = const ApiFailure(
      code: ApiErrorCode.staleDiscoveryContext,
      statusCode: 409,
    );
    expect(await send(), SwipeOutcome.staleContext);
    expect(outbox.saved, isEmpty);
  });

  test('drops a pair that was already decided', () async {
    repository.error = const ApiFailure(
      code: ApiErrorCode.actionConflict,
      statusCode: 409,
    );
    expect(await send(), SwipeOutcome.dropped);
    expect(await send(), SwipeOutcome.dropped);
  });

  test('asks the gates to re-run when the account cannot swipe', () async {
    repository.error = const ApiFailure(
      code: ApiErrorCode.accountSuspended,
      statusCode: 403,
    );
    expect(await send(), SwipeOutcome.gate);
    expect(outbox.saved, isEmpty);
  });

  test('never queues the same key twice', () async {
    repository.error = const NetworkFailure();
    await send();
    await send();
    expect(outbox.saved, hasLength(1));
  });
}
