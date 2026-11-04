import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/onboarding/application/master_data_providers.dart';
import 'package:oma_app/features/onboarding/application/today.dart';
import 'package:oma_app/features/onboarding/domain/entities/master_option.dart';
import 'package:oma_app/features/onboarding/domain/entities/onboarding_draft.dart';
import 'package:oma_app/features/onboarding/domain/repositories/master_data_repository.dart';
import 'package:oma_app/features/onboarding/presentation/steps/about_you_screen.dart';
import 'package:oma_app/features/onboarding/presentation/steps/basics_screen.dart';
import 'package:oma_app/features/onboarding/presentation/steps/personality_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

MasterOption _o(String id, String label, [String? cat]) =>
    MasterOption(id: id, label: label, categoryId: cat);

final _data = <MasterDataType, List<MasterOption>>{
  MasterDataType.gender: [_o('g-w', 'Woman'), _o('g-m', 'Man')],
  MasterDataType.showMe: [
    _o('s-m', 'Men'),
    _o('s-w', 'Women'),
    _o('s-e', 'Everyone'),
  ],
  MasterDataType.lookingFor: [
    for (final l in [
      'Long-term',
      'Life partner',
      'Marriage',
      'Short-term',
      'Have fun',
      'Casual',
      'Ethical non-monogamy',
    ])
      _o('lf-$l', l),
  ],
  MasterDataType.religion: [_o('r-islam', 'Islam'), _o('r-kr', 'Kristen')],
  MasterDataType.personality: [_o('p-infj', 'INFJ'), _o('p-entp', 'ENTP')],
  MasterDataType.hobbyCategory: [
    _o('c-out', 'Outdoor'),
    _o('c-in', 'Indoor'),
    _o('c-game', 'Gaming'),
  ],
  MasterDataType.university: [
    _o('u-ui', 'Universitas Indonesia'),
    _o('u-itb', 'Institut Teknologi Bandung'),
  ],
};

final _hobbies = <String, List<MasterOption>>{
  'c-out': [
    for (final h in ['Freediving', 'Hiking', 'Running', 'Padel'])
      _o('h-$h', h, 'c-out'),
  ],
  'c-in': [
    for (final h in ['Coffee', 'Reading', 'Cooking', 'Bouldering'])
      _o('h-$h', h, 'c-in'),
  ],
  'c-game': [
    for (final h in ['Switch', 'PS5', 'PC', 'Mobile']) _o('h-$h', h, 'c-game'),
  ],
};

class FakeMasterData implements MasterDataRepository {
  final calls = <MasterDataType, int>{};
  Object? failWith;

  @override
  Future<MasterDataPage> page(
    MasterDataType type, {
    String? query,
    String? categoryId,
    int page = 1,
    int limit = 20,
  }) async {
    calls[type] = (calls[type] ?? 0) + 1;
    if (failWith != null) throw failWith!;
    var items = type == MasterDataType.hobby
        ? _hobbies[categoryId] ?? _hobbies.values.expand((h) => h).toList()
        : _data[type]!;
    if (query != null && query.isNotEmpty) {
      items = items
          .where((o) => o.label.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
    return MasterDataPage(
      items: items,
      page: 1,
      totalPages: categoryId == 'c-out' ? 2 : 1,
    );
  }
}

OnboardingDraft _basics() => OnboardingDraft(
  userId: 'u1',
  fullName: 'Rania',
  birthdate: DateTime(1998, 4, 2),
  genderId: 'g-w',
  showMeOptionId: 's-m',
);

void main() {
  late FakeAuthRepository auth;
  late MemoryDraftStore store;
  late FakeMasterData master;

  setUp(() {
    auth = FakeAuthRepository(testUser);
    store = MemoryDraftStore();
    master = FakeMasterData();
  });

  List<Override> overrides() => [
    ...baseOverrides(
      auth: auth,
      accounts: FakeAccountRepository(account()),
      drafts: store,
    ),
    masterDataRepositoryProvider.overrideWithValue(master),
    todayProvider.overrideWithValue(DateTime(2026, 11, 4)),
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    GoldenTheme theme = GoldenTheme.lagoon,
  }) async {
    await pumpScreen(tester, screen, theme: theme, overrides: overrides());
    await tester.pumpAndSettle();
  }

  bool nextEnabled(WidgetTester tester) =>
      tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text('Next'),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed !=
      null;

  group('M06 The basics', () {
    testWidgets('fills the draft and enables Next', (tester) async {
      await pump(tester, const BasicsScreen());
      expect(find.text('Step 1 of 6'), findsOneWidget);
      expect(nextEnabled(tester), isFalse);

      await tester.enterText(find.byType(TextField).first, 'Rania');
      await tester.tap(find.text('Woman'));
      await tester.tap(find.text('Men'));
      await tester.pumpAndSettle();
      expect(nextEnabled(tester), isFalse, reason: 'birthdate missing');

      await _pickDate(tester, '04/02/1998');
      expect(nextEnabled(tester), isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(store.saved?.fullName, 'Rania');
      expect(store.saved?.genderId, 'g-w');
      expect(store.saved?.birthdate, DateTime(1998, 4, 2));
    });

    testWidgets('under 18 shows the error, blocks Next, saves nothing', (
      tester,
    ) async {
      store.saved = _basics().copyWith(birthdate: const Nullable(null));
      await pump(tester, const BasicsScreen());
      await _pickDate(tester, '11/05/2008');
      expect(
        find.text('You need to be 18 or older to use OMA.'),
        findsOneWidget,
      );
      expect(nextEnabled(tester), isFalse);
      expect(store.saved?.birthdate, isNull);
    });

    goldenBothThemes('m06_basics', (tester, theme) async {
      store.saved = _basics();
      await pump(tester, const BasicsScreen(), theme: theme);
    });

    goldenBothThemes('m06_basics_under_18', (tester, theme) async {
      store.saved = _basics().copyWith(birthdate: const Nullable(null));
      await pump(tester, const BasicsScreen(), theme: theme);
      await _pickDate(tester, '11/05/2010');
    });
  });

  group('M07 About you', () {
    testWidgets('validates height and weight ranges', (tester) async {
      store.saved = _basics();
      await pump(tester, const AboutYouScreen());
      await tester.enterText(find.byType(TextField).at(1), '260');
      await tester.enterText(find.byType(TextField).at(2), '20');
      await tester.pump();
      expect(find.text('Between 100 and 250 cm.'), findsOneWidget);
      expect(find.text('Between 25 and 300 kg.'), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('university search picks and saves', (tester) async {
      store.saved = _basics();
      await pump(tester, const AboutYouScreen());
      await tester.ensureVisible(find.text('Your university (optional)'));
      await tester.tap(find.text('Your university (optional)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'bandung');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Universitas Indonesia'), findsNothing);
      await tester.tap(find.text('Institut Teknologi Bandung'));
      await tester.pumpAndSettle();
      expect(store.saved?.universityId, 'u-itb');
      expect(find.text('Institut Teknologi Bandung'), findsOneWidget);
    });

    goldenBothThemes('m07_about_you', (tester, theme) async {
      store.saved = _basics().copyWith(
        bio: const Nullable(
          'Weekend freediver, weekday coffee snob. Dreaming of opening a '
          'dive school in Bali.',
        ),
        lookingForIds: const ['lf-Long-term', 'lf-Life partner'],
        heightCm: const Nullable(165),
        weightKg: const Nullable(55),
        universityId: const Nullable('u-ui'),
        universityName: const Nullable('Universitas Indonesia'),
      );
      await pump(tester, const AboutYouScreen(), theme: theme);
    });

    goldenBothThemes('m07_about_you_invalid', (tester, theme) async {
      store.saved = _basics();
      await pump(tester, const AboutYouScreen(), theme: theme);
      await tester.enterText(find.byType(TextField).at(1), '260');
      await tester.pump();
    });
  });

  group('M08 Personality and hobbies', () {
    testWidgets('needs a hobby; picks go to the draft', (tester) async {
      store.saved = _basics();
      await pump(tester, const PersonalityScreen());
      expect(nextEnabled(tester), isFalse);
      await tester.tap(find.text('Freediving'));
      await tester.pumpAndSettle();
      expect(nextEnabled(tester), isTrue);
      expect(store.saved?.hobbyIds, ['h-Freediving']);
      expect(find.text('More…'), findsOneWidget);
    });

    testWidgets('master data loads once per session', (tester) async {
      store.saved = _basics();
      await pump(tester, const PersonalityScreen());
      await tester.tap(find.text('Freediving'));
      await tester.pumpAndSettle();
      expect(master.calls[MasterDataType.hobbyCategory], 1);
      expect(master.calls[MasterDataType.religion], 1);
    });

    testWidgets('load failure shows Try again and keeps answers', (
      tester,
    ) async {
      store.saved = _basics().copyWith(hobbyIds: const ['h-Hiking']);
      master.failWith = const NetworkFailure();
      await pump(tester, const PersonalityScreen());
      expect(find.text('Try again'), findsWidgets);
      master.failWith = null;
      while (find.text('Try again').evaluate().isNotEmpty) {
        await tester.tap(find.text('Try again').first);
        await tester.pumpAndSettle();
      }
      expect(find.text('Hiking'), findsOneWidget);
      expect(store.saved?.hobbyIds, ['h-Hiking']);
    });

    goldenBothThemes('m08_personality', (tester, theme) async {
      store.saved = _basics().copyWith(
        ambition: const Nullable('Open a dive school in Bali'),
        religionId: const Nullable('r-islam'),
        personalityTypeId: const Nullable('p-infj'),
        hobbyIds: const ['h-Freediving', 'h-Coffee', 'h-Switch'],
      );
      await pump(tester, const PersonalityScreen(), theme: theme);
    });
  });
}

Future<void> _pickDate(WidgetTester tester, String mmddyyyy) async {
  await tester.tap(find.byIcon(Icons.calendar_today_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
    mmddyyyy,
  );
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}
