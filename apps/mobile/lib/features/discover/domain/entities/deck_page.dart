import 'package:meta/meta.dart';

import 'deck_card.dart';

/// One batch of the deck. Lives 30 minutes and also ends at WIB midnight.
@immutable
class DeckPage {
  const DeckPage({
    required this.contextId,
    required this.cards,
    this.nextCursor,
    this.deckExpiresAt,
    this.endReason,
  });

  factory DeckPage.fromJson(Map<String, Object?> json) => DeckPage(
    contextId: json['context_id'] as String? ?? '',
    cards: [
      for (final card in (json['cards'] as List? ?? const []))
        DeckCard.fromJson((card as Map).cast()),
    ],
    nextCursor: json['next_cursor'] as String?,
    deckExpiresAt: json['deck_expires_at'] is String
        ? DateTime.tryParse(json['deck_expires_at']! as String)
        : null,
    endReason: json['end_reason'] as String?,
  );

  final String contextId;
  final List<DeckCard> cards;
  final String? nextCursor;
  final DateTime? deckExpiresAt;
  final String? endReason;

  bool get isExhausted => endReason == 'candidate_pool_exhausted';
}
