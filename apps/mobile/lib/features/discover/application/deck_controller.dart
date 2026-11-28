import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/failure.dart';
import '../../usage/application/usage_providers.dart';
import '../domain/deck_state.dart';
import '../domain/entities/deck_card.dart';
import '../domain/entities/deck_page.dart';
import '../domain/entities/swipe_command.dart';
import '../domain/entities/swipe_kind.dart';
import '../domain/usecases/submit_swipe.dart';
import 'deck_providers.dart';

/// Owns the deck: one batch at a time, prefetched five cards before the end,
/// and the optimistic removal plus rollback rules from SA section 5.
class DeckController extends AsyncNotifier<DeckState> {
  static const batchSize = 20;
  static const prefetchAt = 5;

  bool _busy = false;
  bool _flushing = false;

  /// Cards already decided in this session. The server never returns them
  /// again, but a stale cursor page could, so they are filtered out here too.
  final Set<String> _decided = {};

  @override
  Future<DeckState> build() => _load();

  Future<DeckState> _load() async {
    try {
      final page = await ref
          .read(deckRepositoryProvider)
          .fetch(limit: batchSize);
      final pending = await ref.read(swipeOutboxProvider).load();
      final pendingIds = {for (final command in pending) command.candidateId};
      final cards = [
        for (final card in page.cards)
          if (!pendingIds.contains(card.id)) card,
      ];
      final queued = await _flushOutbox();
      return _stateFor(page, cards).copyWith(queued: queued);
    } on NetworkFailure {
      return const DeckState(status: DeckStatus.offlineEmpty);
    } on ApiFailure catch (failure) {
      return _errorState(failure);
    } on UnexpectedFailure catch (failure) {
      return _errorState(failure);
    }
  }

  DeckState _stateFor(DeckPage page, List<DeckCard> cards) => DeckState(
    cards: cards,
    contextId: page.contextId,
    nextCursor: page.nextCursor,
    expiresAt: page.deckExpiresAt,
    status: cards.isEmpty && page.isExhausted
        ? DeckStatus.outOfFish
        : DeckStatus.ready,
  );

  DeckState _errorState(Object error) => DeckState(
    status: error is NetworkFailure
        ? DeckStatus.offlineEmpty
        : DeckStatus.error,
    error: error,
  );

  /// Removes the top card, sends the decision, and rolls back when the server
  /// refuses it. Returns the outcome so the screen can show the sheet.
  Future<SwipeOutcome> swipe(SwipeKind kind) async {
    final current = state.value;
    final card = current?.top;
    final contextId = current?.contextId;
    if (current == null || card == null || contextId == null) {
      return SwipeOutcome.dropped;
    }

    final command = SwipeCommand(
      candidateId: card.id,
      kind: kind,
      contextKind: 'regular_deck',
      contextId: contextId,
      idempotencyKey: const Uuid().v4(),
      createdAt: DateTime.now(),
    );

    _decided.add(card.id);
    final remaining = current.cards.sublist(1);
    state = AsyncData(
      current.copyWith(
        cards: remaining,
        status: _statusAfterRemoval(current, remaining),
        clearError: true,
      ),
    );
    if (kind.spendsLike) {
      ref.read(dailyUsageProvider.notifier).spendLike();
    }

    final outcome = await ref.read(submitSwipeProvider)(command);

    switch (outcome) {
      case SwipeOutcome.accepted:
      case SwipeOutcome.dropped:
        await _afterSwipe();
      case SwipeOutcome.queued:
        _markQueued();
        await _afterSwipe();
      case SwipeOutcome.likeLimit:
        _rollback(card, DeckStatus.outOfLikes);
        unawaited(ref.read(dailyUsageProvider.notifier).refresh());
      case SwipeOutcome.superLikeEmpty:
        _rollback(card, null);
      case SwipeOutcome.staleContext:
        await _reloadSilently();
    }
    return outcome;
  }

  DeckStatus _statusAfterRemoval(DeckState current, List<DeckCard> remaining) {
    if (remaining.isNotEmpty) return DeckStatus.ready;
    if (current.nextCursor != null) return DeckStatus.ready;
    return DeckStatus.outOfFish;
  }

  void _markQueued() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(queued: true));
  }

  void _rollback(DeckCard card, DeckStatus? status) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        cards: [card, ...current.cards],
        status: status ?? DeckStatus.ready,
      ),
    );
  }

  Future<void> _afterSwipe() async {
    final current = state.value;
    if (current == null) return;
    if (current.cards.isEmpty) {
      await _nextBatch();
      return;
    }
    if (current.cards.length <= prefetchAt && current.nextCursor != null) {
      await _prefetch();
    }
  }

  Future<void> _prefetch() async {
    final current = state.value;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || _busy) return;
    _busy = true;
    try {
      final page = await ref
          .read(deckRepositoryProvider)
          .fetch(limit: batchSize, cursor: cursor);
      final latest = state.value;
      if (latest == null) return;
      final seen = {for (final card in latest.cards) card.id};
      final added = [
        for (final card in page.cards)
          if (!seen.contains(card.id) && !_decided.contains(card.id)) card,
      ];
      state = AsyncData(
        latest.copyWith(
          cards: [...latest.cards, ...added],
          nextCursor: page.nextCursor,
          expiresAt: page.deckExpiresAt,
          status: latest.cards.isEmpty && added.isEmpty && page.isExhausted
              ? DeckStatus.outOfFish
              : latest.status,
        ),
      );
      unawaited(_flushOutbox());
    } on ApiFailure catch (failure) {
      if (failure.code == ApiErrorCode.staleDiscoveryContext ||
          failure.code == ApiErrorCode.invalidCursor) {
        await _reloadSilently();
      }
    } on NetworkFailure {
      // Keep the cards already in memory; the next swipe retries.
    } finally {
      _busy = false;
    }
  }

  Future<void> _nextBatch() async {
    if (_busy) return;
    _busy = true;
    try {
      final pending = await ref.read(swipeOutboxProvider).load();
      if (pending.isNotEmpty) {
        await _flushOutbox();
        final stillPending = await ref.read(swipeOutboxProvider).load();
        if (stillPending.isNotEmpty) return;
      }
      final page = await ref
          .read(deckRepositoryProvider)
          .fetch(limit: batchSize);
      final latest = state.value;
      if (latest == null) return;
      final seen = {for (final card in latest.cards) card.id};
      final added = [
        for (final card in page.cards)
          if (!seen.contains(card.id) && !_decided.contains(card.id)) card,
      ];
      state = AsyncData(
        latest.copyWith(
          cards: [...latest.cards, ...added],
          contextId: page.contextId,
          nextCursor: page.nextCursor,
          expiresAt: page.deckExpiresAt,
          status: added.isEmpty && page.isExhausted
              ? DeckStatus.outOfFish
              : DeckStatus.ready,
        ),
      );
    } on NetworkFailure {
      final latest = state.value;
      if (latest != null && latest.cards.isEmpty) {
        state = AsyncData(latest.copyWith(status: DeckStatus.offlineEmpty));
      }
    } on ApiFailure catch (failure) {
      final latest = state.value;
      if (latest != null && latest.cards.isEmpty) {
        state = AsyncData(
          latest.copyWith(status: DeckStatus.error, error: failure),
        );
      }
    } finally {
      _busy = false;
    }
  }

  /// Sends every pending command. Returns true when something is still queued.
  Future<bool> _flushOutbox() async {
    if (_flushing) return false;
    _flushing = true;
    try {
      final outbox = ref.read(swipeOutboxProvider);
      final pending = await outbox.load();
      if (pending.isEmpty) return false;
      final remaining = <SwipeCommand>[];
      for (final command in pending) {
        final outcome = await ref.read(submitSwipeProvider)(command);
        if (outcome == SwipeOutcome.queued) remaining.add(command);
      }
      await outbox.save(remaining);
      return remaining.isNotEmpty;
    } finally {
      _flushing = false;
    }
  }

  Future<void> _reloadSilently() async {
    final next = await _load();
    state = AsyncData(next);
  }

  /// Re-reads the deck from scratch. Used by Try again and on resume.
  Future<void> reload() async {
    state = const AsyncLoading();
    state = AsyncData(await _load());
  }
}

final deckControllerProvider = AsyncNotifierProvider<DeckController, DeckState>(
  DeckController.new,
  retry: (_, _) => null,
);
