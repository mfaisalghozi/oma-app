import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/features/describe/presentation/describe_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    int searchesAvailable = 3,
    List<Override> extra = const [],
    GoldenTheme theme = GoldenTheme.lagoon,
  }) {
    final auth = FakeAuthRepository(testUser);
    return pumpScreen(
      tester,
      const Scaffold(body: DescribeScreen()),
      theme: theme,
      overrides: [
        ...baseOverrides(
          auth: auth,
          accounts: FakeAccountRepository(account()),
          usage: FakeUsageRepository(
            testUsage(searchesAvailable: searchesAvailable),
          ),
        ),
        ...extra,
      ],
    );
  }

  testWidgets('draws the box, the counter and the three examples', (
    tester,
  ) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('Describe the person you want'), findsOneWidget);
    expect(find.text('Try one of these'), findsOneWidget);
    expect(find.textContaining('Cowok min 180 cm'), findsOneWidget);
    expect(find.textContaining('It never reads photos'), findsOneWidget);
    expect(find.text('Find matches'), findsOneWidget);
  });

  testWidgets('a prompt fills the box', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Woman in South Jakarta'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains('Woman in South Jakarta'));
  });

  testWidgets('over 500 characters shows the limit error', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'a' * 501);
    await tester.pump();

    expect(find.text('Keep it under 500 characters'), findsOneWidget);
  });

  testWidgets('no searches left shows the red counter and PRO', (tester) async {
    await pump(tester, searchesAvailable: 0);
    await tester.pumpAndSettle();

    expect(find.text("That's your 3 searches for today"), findsOneWidget);
    expect(find.text('Get 20 searches a day with PRO'), findsOneWidget);
    expect(find.text('See my last results'), findsNothing);
  });
}
