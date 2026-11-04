import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/theme/oma_theme.dart';

bool _fontsLoaded = false;

/// Loads the bundled Nunito and Material icons so goldens show real glyphs
/// instead of the test font's boxes.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  final nunito = FontLoader('Nunito');
  for (final w in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
    nunito.addFont(rootBundle.load('assets/fonts/Nunito-$w.ttf'));
  }
  await nunito.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  _fontsLoaded = true;
}

enum GoldenTheme { lagoon, deepSea }

/// Pumps [child] on a 390 x 844 phone (the v0.1 board size) in [theme].
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  GoldenTheme theme = GoldenTheme.lagoon,
  List<Override> overrides = const [],
}) async {
  await loadAppFonts();
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme == GoldenTheme.lagoon
            ? OmaTheme.lagoon()
            : OmaTheme.deepSea(),
        home: child,
      ),
    ),
  );
}

/// Runs [body] once per theme with a golden named `<name>_<theme>.png`.
void goldenBothThemes(
  String name,
  Future<void> Function(WidgetTester tester, GoldenTheme theme) body,
) {
  for (final theme in GoldenTheme.values) {
    testWidgets('$name (${theme.name})', (tester) async {
      await body(tester, theme);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/${name}_${theme.name}.png'),
      );
    }, tags: ['golden']);
  }
}
