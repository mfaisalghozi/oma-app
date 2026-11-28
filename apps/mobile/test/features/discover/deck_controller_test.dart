import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/api/api_client.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/discover/application/deck_controller.dart';
import 'package:oma_app/features/discover/application/deck_providers.dart';
import 'package:oma_app/features/discover/domain/deck_state.dart';
import 'package:oma_app/features/discover/domain/entities/swipe_kind.dart';
import 'package:oma_app/features/discover/domain/usecases/submit_swipe.dart';
import 'package:oma_app/features/usage/application/usage_providers.dart';

import '../../helpers/deck_fakes.dart';
import '../../helpers/fakes.dart';

void main() {
  late FakeDeckRepository deck;
  late FakeSwipeRepository swipe;
  late MemorySwipeOutbox outbox;
  var gateRefreshes = 0;

  setUp(() {
    deck = FakeDeckRepository();
    swipe = FakeSwipeRepository();
    outbox = MemorySwipeOutbox();
    gateRefreshes = 0;
  });

  ProviderContainer make() => ProviderContainer(
    overrides: [
      deckRepositoryProvider.overrideWithValue(deck),
      swipeRepositoryProvider.overrideWithValue(swipe),
      swipeOutboxProvider.overrideWithValue(outbox),
      usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
      gateRefreshProvider.overrideWithValue(() async => gateRefreshes++),
    ],
  );

  Future<DeckState> load(ProviderContainer container) =>
      container.read(deckControllerProvider.future);

  test('loads one batch of 20 without a cursor', () async {
    deck.handler = (limit, cursor) => deckPage(
      cards: [
        deckCard(id: 'a'),
        deckCard(id: 'b'),
      ],
      nextCursor: 'cur',
    );
    final container = make();
    addTearDown(container.dispose);

    final state = await load(container);
    expect(state.cards.map((card) => card.id), ['a', 'b']);
    expect(deck.calls.single.$1, 20);
    expect(deck.calls.single.$2, isNull);
    expect(state.status, DeckStatus.ready);
  });

  test('a like removes the card at once and sends the decision', () async {
    deck.handler = (_, _) => deckPage(
      cards: [
        deckCard(id: 'a'),
        deckCard(id: 'b'),
      ],
      nextCursor: 'cur',
    );
    final container = make();
    addTearDown(container.dispose);
    await load(container);

    final outcome = await container
        .read(deckControllerProvider.notifier)
        .swipe(SwipeKind.like);

    expect(outcome, SwipeOutcome.accepted);
    final state = container.read(deckControllerProvider).value!;
    expect(state.cards.single.id, 'b');
    final sent = swipe.submitted.single;
    expect(sent.candidateId, 'a');
    expect(sent.kind, SwipeKind.like);
    expect(sent.contextId, 'ctx-1');
  });

  test('a refused like puts the card back and shows Out of likes', () async {
    deck.handler = (_, _) => deckPage(
      cards: [deckCard(id: 'a')],
      nextCursor: 'cur',
    );
    swipe.error = const ApiFailure(
      code: ApiErrorCode.likeLimitReached,
      statusCode: 429,
    );
    final container = make();
    addTearDown(container.dispose);
    await load(container);

    final outcome = await container
        .read(deckControllerProvider.notifier)
        .swipe(SwipeKind.like);

    expect(outcome, SwipeOutcome.likeLimit);
    final state = container.read(deckControllerProvider).value!;
    expect(state.cards.single.id, 'a');
    expect(state.status, DeckStatus.outOfLikes);
  });

  test('an empty super-like balance puts the card back', () async {
    deck.handler = (_, _) => deckPage(cards: [deckCard(id: 'a')]);
    swipe.error = const ApiFailure(
      code: ApiErrorCode.superLikeBalanceEmpty,
      statusCode: 429,
    );
    final container = make();
    addTearDown(container.dispose);
    await load(container);

    final outcome = await container
        .read(deckControllerProvider.notifier)
        .swipe(SwipeKind.superLike);

    expect(outcome, SwipeOutcome.superLikeEmpty);
    expect(container.read(deckControllerProvider).value!.cards.single.id, 'a');
  });

  test('offline keeps the card away and marks the deck queued', () async {
    deck.handler = (_, _) => deckPage(
      cards: [
        deckCard(id: 'a'),
        deckCard(id: 'b'),
      ],
      nextCursor: 'cur',
    );
    swipe.error = const NetworkFailure();
    final container = make();
    addTearDown(container.dispose);
    await load(container);

    final outcome = await container
        .read(deckControllerProvider.notifier)
        .swipe(SwipeKind.pass);

    expect(outcome, SwipeOutcome.queued);
    final state = container.read(deckControllerProvider).value!;
    expect(state.cards.single.id, 'b');
    expect(state.queued, isTrue);
    expect(outbox.saved.single.candidateId, 'a');
  });

  test('prefetches with the cursor when five cards are left', () async {
    var calls = 0;
    deck.handler = (limit, cursor) {
      calls++;
      if (cursor == null) {
        return deckPage(
          cards: [for (var i = 0; i < 6; i++) deckCard(id: 'c$i')],
          nextCursor: 'cur',
        );
      }
      return deckPage(
        contextId: 'ctx-2',
        cards: [deckCard(id: 'extra')],
      );
    };
    final container = make();
    addTearDown(container.dispose);
    await load(container);

    await container.read(deckControllerProvider.notifier).swipe(SwipeKind.pass);

    expect(calls, 2);
    expect(deck.calls[1].$2, 'cur');
    final state = container.read(deckControllerProvider).value!;
    expect(state.cards, hasLength(6));
    expect(state.cards.last.id, 'extra');
  });

  test('asks for a new batch once the queue is empty', () async {
    var calls = 0;
    deck.handler = (limit, cursor) => ++calls == 1
        ? deckPage(cards: [deckCard(id: 'only')], nextCursor: null)
        : deckPage(
            contextId: 'ctx-2',
            cards: [deckCard(id: 'fresh')],
          );
    final container = make();
    addTearDown(container.dispose);
    await load(container);

    await container.read(deckControllerProvider.notifier).swipe(SwipeKind.pass);

    expect(deck.calls, hasLength(2));
    expect(deck.calls[1].$2, isNull);
    final state = container.read(deckControllerProvider).value!;
    expect(state.cards.single.id, 'fresh');
    expect(state.contextId, 'ctx-2');
  });

  test('an exhausted empty batch is Out of fish', () async {
    deck.handler = (_, _) => deckPage(cards: const [], exhausted: true);
    final container = make();
    addTearDown(container.dispose);

    final state = await load(container);
    expect(state.status, DeckStatus.outOfFish);
    expect(state.cards, isEmpty);
  });

  test('no connection with no cards is the offline state', () async {
    deck.handler = (_, _) => throw const NetworkFailure();
    final container = make();
    addTearDown(container.dispose);

    final state = await load(container);
    expect(state.status, DeckStatus.offlineEmpty);
  });

  test('a 5xx is the error state, not offline', () async {
    deck.handler = (_, _) => throw const ApiFailure(
      code: ApiErrorCode.internalServerError,
      statusCode: 500,
    );
    final container = make();
    addTearDown(container.dispose);

    final state = await load(container);
    expect(state.status, DeckStatus.error);
    expect(state.error, isA<ApiFailure>());
  });

  test('a stale context reloads the deck silently', () async {
    var calls = 0;
    deck.handler = (_, _) {
      calls++;
      return deckPage(
        cards: [deckCard(id: 'c$calls')],
        nextCursor: 'cur',
      );
    };
    swipe.error = const ApiFailure(
      code: ApiErrorCode.staleDiscoveryContext,
      statusCode: 409,
    );
    final container = make();
    addTearDown(container.dispose);
    await load(container);

    final outcome = await container
        .read(deckControllerProvider.notifier)
        .swipe(SwipeKind.pass);

    expect(outcome, SwipeOutcome.staleContext);
    expect(calls, 2);
    expect(container.read(deckControllerProvider).value!.cards.single.id, 'c2');
  });

  test('a 403 from the deck re-runs the gates', () async {
    deck.handler = (_, _) => throw const ApiFailure(
      code: ApiErrorCode.accountSuspended,
      statusCode: 403,
    );
    final container = make();
    addTearDown(container.dispose);

    final state = await load(container);
    expect(state.status, DeckStatus.error);
    expect(gateRefreshes, 1);
  });

  test('a 403 on an action puts the card back and re-runs the gates', () async {
    deck.handler = (_, _) => deckPage(cards: [deckCard(id: 'a')]);
    swipe.error = const ApiFailure(
      code: ApiErrorCode.accountFrozen,
      statusCode: 403,
    );
    final container = make();
    addTearDown(container.dispose);
    await load(container);

    final outcome = await container
        .read(deckControllerProvider.notifier)
        .swipe(SwipeKind.pass);

    expect(outcome, SwipeOutcome.gate);
    expect(container.read(deckControllerProvider).value!.cards.single.id, 'a');
    expect(gateRefreshes, 1);
  });

  test('pending decisions are flushed on the next load', () async {
    deck.handler = (_, _) => deckPage(cards: [deckCard(id: 'a')]);
    outbox.saved = [swipeCommand(id: 'old', key: 'k-old')];
    final container = make();
    addTearDown(container.dispose);
    await load(container);

    expect(swipe.submitted.single.candidateId, 'old');
    expect(outbox.saved, isEmpty);
    expect(container.read(deckControllerProvider).value!.queued, isFalse);
  });
}
