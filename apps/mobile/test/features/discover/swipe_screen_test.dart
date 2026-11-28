import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/features/discover/application/deck_controller.dart';
import 'package:oma_app/features/discover/domain/deck_state.dart';
import 'package:oma_app/features/discover/domain/entities/swipe_kind.dart';
import 'package:oma_app/features/discover/domain/usecases/submit_swipe.dart';
import 'package:oma_app/features/discover/presentation/swipe_screen.dart';

import '../../helpers/deck_fakes.dart';
import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

class _StubDeck extends DeckController {
  _StubDeck(this.initial, {this.outcome = SwipeOutcome.accepted});

  final DeckState initial;
  final SwipeOutcome outcome;

  @override
  Future<DeckState> build() async => initial;

  @override
  Future<SwipeOutcome> swipe(SwipeKind kind) async => outcome;

  @override
  Future<void> reload() async {}
}

void main() {
  List<Override> overrides(DeckState state, {SwipeOutcome? outcome}) {
    final auth = FakeAuthRepository(testUser);
    return [
      ...baseOverrides(auth: auth, accounts: FakeAccountRepository(account())),
      deckControllerProvider.overrideWith(
        () => _StubDeck(state, outcome: outcome ?? SwipeOutcome.accepted),
      ),
    ];
  }

  Future<void> pump(
    WidgetTester tester,
    DeckState state, {
    SwipeOutcome? outcome,
    bool describeEnabled = false,
    GoldenTheme theme = GoldenTheme.lagoon,
  }) => pumpScreen(
    tester,
    SwipeScreen(describeEnabled: describeEnabled),
    theme: theme,
    overrides: overrides(state, outcome: outcome),
  );

  testWidgets('draws the top card with name, distance, ambition and tags', (
    tester,
  ) async {
    await pump(
      tester,
      DeckState(
        cards: [
          deckCard(
            id: 'a',
            name: 'Dimas',
            age: 28,
            distance: 4,
            ambition: 'Run the Jakarta Marathon under 4 hours',
            hobbies: const ['Running', 'Coffees'],
            personality: 'ENFP',
          ),
        ],
        contextId: 'ctx',
      ),
    );
    await tester.pump();

    expect(find.text('Dimas, 28'), findsOneWidget);
    expect(find.text('4 km away'), findsOneWidget);
    expect(find.text('Run the Jakarta Marathon under 4 hours'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('ENFP'), findsOneWidget);
  });

  testWidgets('Out of likes names the daily limit and the reset', (
    tester,
  ) async {
    await pump(tester, const DeckState(status: DeckStatus.outOfLikes));
    await tester.pumpAndSettle();

    expect(find.text("That's your 30 likes for today"), findsOneWidget);
    expect(find.textContaining('More likes at'), findsOneWidget);
    expect(find.text('See PRO'), findsOneWidget);
    expect(find.text('Finish my profile'), findsOneWidget);
  });

  testWidgets('Out of fish offers Describe only when it is enabled', (
    tester,
  ) async {
    await pump(
      tester,
      const DeckState(status: DeckStatus.outOfFish),
      describeEnabled: true,
    );
    await tester.pumpAndSettle();
    expect(find.text("You've seen everyone new nearby"), findsOneWidget);
    expect(find.text('Describe who I want'), findsOneWidget);

    await pump(tester, const DeckState(status: DeckStatus.outOfFish));
    await tester.pumpAndSettle();
    expect(find.text('Describe who I want'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('offline shows its own card', (tester) async {
    await pump(tester, const DeckState(status: DeckStatus.offlineEmpty));
    await tester.pumpAndSettle();
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('error keeps the word "lost" promise and offers retry', (
    tester,
  ) async {
    await pump(tester, const DeckState(status: DeckStatus.error));
    await tester.pumpAndSettle();
    expect(find.text("Something didn't load"), findsOneWidget);
    expect(find.text('Nothing was lost. Please try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('comment opens the Coming soon sheet', (tester) async {
    await pump(
      tester,
      DeckState(
        cards: [deckCard(id: 'a')],
        contextId: 'ctx',
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Comments are coming soon'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('an empty super-like balance explains the card came back', (
    tester,
  ) async {
    await pump(
      tester,
      DeckState(
        cards: [deckCard(id: 'a')],
        contextId: 'ctx',
      ),
      outcome: SwipeOutcome.superLikeEmpty,
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.star_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Super likes are coming soon'), findsOneWidget);
    expect(find.textContaining('Nothing was charged'), findsOneWidget);
  });

  testWidgets('an offline deck with cards shows the banner', (tester) async {
    await pump(
      tester,
      DeckState(
        cards: [deckCard(id: 'a')],
        contextId: 'ctx',
        queued: true,
      ),
    );
    await tester.pump();
    expect(find.textContaining("You're offline"), findsOneWidget);
  });
}
