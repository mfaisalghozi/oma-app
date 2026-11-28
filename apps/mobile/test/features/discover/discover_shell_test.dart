import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oma_app/app/shell/app_shell.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/core/theme/oma_theme.dart';
import 'package:oma_app/core/widgets/oma_tab_bar.dart';
import 'package:oma_app/features/discover/presentation/discover_mode.dart';
import 'package:oma_app/features/discover/presentation/discover_shell.dart';
import 'package:oma_app/features/discover/presentation/widgets/super_like_chip.dart';

import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

Future<void> _pump(
  WidgetTester tester, {
  GoldenTheme theme = GoldenTheme.lagoon,
  bool describeEnabled = false,
  List<Override> overrides = const [],
  String initialLocation = '/discover',
}) async {
  await loadAppFonts();
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/discover',
        builder: (context, state) => Scaffold(
          body: DiscoverShell(
            mode: DiscoverMode.fromQuery(state.uri.queryParameters['mode']),
            describeEnabled: describeEnabled,
          ),
          bottomNavigationBar: OmaTabBar(
            destinations: appTabDestinations,
            currentIndex: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: theme == GoldenTheme.lagoon
            ? OmaTheme.lagoon()
            : OmaTheme.deepSea(),
        routerConfig: router,
      ),
    ),
  );
}

void main() {
  late FakeAuthRepository auth;
  late FakeUsageRepository usage;

  setUp(() {
    auth = FakeAuthRepository(testUser);
    usage = FakeUsageRepository();
  });

  List<Override> overrides() => baseOverrides(
    auth: auth,
    accounts: FakeAccountRepository(account()),
    usage: usage,
  );

  testWidgets('shows the likes pill from the usage endpoint', (tester) async {
    await _pump(tester, overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.text('12 of 30 likes left today'), findsOneWidget);
    expect(usage.calls, 1);
  });

  testWidgets('hides the pill when usage fails', (tester) async {
    usage.error = const NetworkFailure();
    await _pump(tester, overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.textContaining('likes left'), findsNothing);
  });

  testWidgets('spent likes show the reset time', (tester) async {
    usage = FakeUsageRepository(testUsage(likesAvailable: 0));
    await _pump(tester, overrides: overrides());
    await tester.pumpAndSettle();
    final local = DateTime.utc(2026, 11, 12, 17).toLocal();
    final clock =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    expect(find.text('0 of 30 likes left · resets $clock'), findsOneWidget);
  });

  testWidgets('switches to describe and shows the searches pill', (
    tester,
  ) async {
    await _pump(tester, describeEnabled: true, overrides: overrides());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Describe'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3 searches left today'), findsOneWidget);
    expect(find.text('Describe who you want'), findsOneWidget);
  });

  testWidgets('hides the switch when describe is disabled', (tester) async {
    await _pump(tester, overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.text('Swipe'), findsNothing);
    expect(find.text('Describe'), findsNothing);
  });

  testWidgets('shows the Ocean Match subtitle under the wordmark', (
    tester,
  ) async {
    await _pump(tester, overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.text('Ocean Match'), findsOneWidget);
  });

  testWidgets('keeps the super-like chip hidden', (tester) async {
    await _pump(tester, overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(SuperLikeChip), findsNothing);
  });

  testWidgets('renders the four tab destinations', (tester) async {
    await _pump(tester, overrides: overrides());
    await tester.pumpAndSettle();
    for (final label in ['Discover', 'Likes you', 'Matches', 'Profile']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}
