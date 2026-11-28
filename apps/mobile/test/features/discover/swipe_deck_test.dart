import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/features/discover/domain/entities/swipe_kind.dart';
import 'package:oma_app/features/discover/presentation/widgets/profile_card.dart';
import 'package:oma_app/features/discover/presentation/widgets/swipe_deck.dart';

import '../../helpers/deck_fakes.dart';
import '../../helpers/golden.dart';

void main() {
  late List<SwipeKind> sent;

  setUp(() => sent = []);

  Future<void> pumpDeck(
    WidgetTester tester, {
    ({int seq, String id, SwipeKind kind})? returning,
    int cards = 2,
  }) => pumpScreen(
    tester,
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SwipeDeck(
          cards: [for (var i = 0; i < cards; i++) deckCard(id: 'c$i')],
          returning: returning,
          onSwipe: (kind) async => sent.add(kind),
          onComment: () {},
        ),
      ),
    ),
  );

  testWidgets('a drag right commits a like', (tester) async {
    await pumpDeck(tester);
    await tester.pump();

    await tester.drag(find.byType(ProfileCard).first, const Offset(220, 0));
    await tester.pumpAndSettle();

    expect(sent, [SwipeKind.like]);
  });

  testWidgets('a drag left commits a pass', (tester) async {
    await pumpDeck(tester);
    await tester.pump();

    await tester.drag(find.byType(ProfileCard).first, const Offset(-220, 0));
    await tester.pumpAndSettle();

    expect(sent, [SwipeKind.pass]);
  });

  testWidgets('a drag up commits a super like', (tester) async {
    await pumpDeck(tester);
    await tester.pump();

    await tester.drag(find.byType(ProfileCard).first, const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(sent, [SwipeKind.superLike]);
  });

  testWidgets('a short drag springs back and sends nothing', (tester) async {
    await pumpDeck(tester);
    await tester.pump();

    await tester.drag(find.byType(ProfileCard).first, const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(sent, isEmpty);
    expect(find.byType(ProfileCard), findsWidgets);
  });

  testWidgets('the like button commits the same decision', (tester) async {
    await pumpDeck(tester);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pumpAndSettle();

    expect(sent, [SwipeKind.like]);
  });

  testWidgets('only the top two cards are built', (tester) async {
    await pumpDeck(tester, cards: 4);
    await tester.pump();

    expect(find.byType(ProfileCard), findsNWidgets(2));
  });

  testWidgets('a refused card stays on screen', (tester) async {
    await pumpDeck(
      tester,
      returning: (seq: 1, id: 'c0', kind: SwipeKind.superLike),
    );
    await tester.pump();

    expect(find.byType(ProfileCard), findsWidgets);
  });
}
