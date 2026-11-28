import 'package:oma_app/features/discover/domain/entities/action_result.dart';
import 'package:oma_app/features/discover/domain/entities/deck_card.dart';
import 'package:oma_app/features/discover/domain/entities/deck_page.dart';
import 'package:oma_app/features/discover/domain/entities/swipe_command.dart';
import 'package:oma_app/features/discover/domain/entities/swipe_kind.dart';
import 'package:oma_app/features/discover/domain/repositories/deck_repository.dart';
import 'package:oma_app/features/discover/domain/repositories/swipe_outbox.dart';
import 'package:oma_app/features/discover/domain/repositories/swipe_repository.dart';

DeckCard deckCard({
  String id = 'c1',
  String name = 'Dimas',
  int age = 28,
  int distance = 4,
  String? ambition = 'Run the Jakarta Marathon under 4 hours',
  List<String> hobbies = const ['Running', 'Coffees'],
  String? personality = 'ENFP',
  int photos = 2,
}) => DeckCard(
  id: id,
  displayName: name,
  age: age,
  approxDistanceKm: distance,
  ambition: ambition,
  photos: [
    for (var index = 0; index < photos; index++)
      DeckPhoto(
        id: '$id-p$index',
        position: index,
        readUrl: 'https://example.test/$id/$index.jpg',
      ),
  ],
  hobbies: [
    for (final hobby in hobbies)
      DeckOption(id: '$id-$hobby', code: hobby.toLowerCase(), label: hobby),
  ],
  personality: personality == null
      ? null
      : DeckOption(id: '$id-p', code: 'enfp', label: personality),
);

SwipeCommand swipeCommand({
  String id = 'c1',
  String key = 'k1',
  SwipeKind kind = SwipeKind.pass,
  String contextId = 'ctx-1',
}) => SwipeCommand(
  candidateId: id,
  kind: kind,
  contextKind: 'regular_deck',
  contextId: contextId,
  idempotencyKey: key,
  createdAt: DateTime.utc(2026, 11, 27),
);

DeckPage deckPage({
  String contextId = 'ctx-1',
  List<DeckCard> cards = const [],
  String? nextCursor,
  bool exhausted = false,
}) => DeckPage(
  contextId: contextId,
  cards: cards,
  nextCursor: nextCursor,
  deckExpiresAt: DateTime.utc(2026, 11, 27, 18),
  endReason: exhausted ? 'candidate_pool_exhausted' : null,
);

class FakeDeckRepository implements DeckRepository {
  FakeDeckRepository([this.handler]);

  DeckPage Function(int limit, String? cursor)? handler;
  final List<(int, String?)> calls = [];

  @override
  Future<DeckPage> fetch({int limit = 20, String? cursor}) async {
    calls.add((limit, cursor));
    final respond = handler;
    if (respond == null) return deckPage(cards: [deckCard()]);
    return respond(limit, cursor);
  }
}

class FakeSwipeRepository implements SwipeRepository {
  final List<SwipeCommand> submitted = [];
  Object? error;
  ActionResult result = const ActionResult(actionId: 'a1', action: 'like');

  @override
  Future<ActionResult> submit(SwipeCommand command) async {
    submitted.add(command);
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

class MemorySwipeOutbox implements SwipeOutbox {
  List<SwipeCommand> saved = [];
  int saves = 0;

  @override
  Future<List<SwipeCommand>> load() async => List.of(saved);

  @override
  Future<void> save(List<SwipeCommand> commands) async {
    saves++;
    saved = List.of(commands);
  }
}
