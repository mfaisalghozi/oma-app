import 'package:meta/meta.dart';

import 'entities/deck_card.dart';

enum DeckStatus { ready, outOfLikes, outOfFish, offlineEmpty, error }

/// What the deck area draws. Cards are not persisted: a cold start refetches.
@immutable
class DeckState {
  const DeckState({
    this.cards = const [],
    this.contextId,
    this.nextCursor,
    this.expiresAt,
    this.status = DeckStatus.ready,
    this.error,
    this.isRefreshing = false,
    this.queued = false,
  });

  final List<DeckCard> cards;
  final String? contextId;
  final String? nextCursor;
  final DateTime? expiresAt;
  final DeckStatus status;
  final Object? error;
  final bool isRefreshing;

  /// True when at least one decision is waiting in the outbox.
  final bool queued;

  DeckCard? get top => cards.isEmpty ? null : cards.first;

  bool get isEmpty => cards.isEmpty;

  DeckState copyWith({
    List<DeckCard>? cards,
    String? contextId,
    String? nextCursor,
    DateTime? expiresAt,
    DeckStatus? status,
    Object? error,
    bool clearError = false,
    bool? isRefreshing,
    bool? queued,
  }) => DeckState(
    cards: cards ?? this.cards,
    contextId: contextId ?? this.contextId,
    nextCursor: nextCursor ?? this.nextCursor,
    expiresAt: expiresAt ?? this.expiresAt,
    status: status ?? this.status,
    error: clearError ? null : (error ?? this.error),
    isRefreshing: isRefreshing ?? this.isRefreshing,
    queued: queued ?? this.queued,
  );
}
