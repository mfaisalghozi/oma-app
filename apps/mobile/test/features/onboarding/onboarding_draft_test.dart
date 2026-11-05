import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/features/auth/application/session_controller.dart';
import 'package:oma_app/features/auth/domain/entities/auth_session.dart';
import 'package:oma_app/features/onboarding/application/onboarding_draft_controller.dart';
import 'package:oma_app/features/onboarding/application/onboarding_resume.dart';
import 'package:oma_app/features/onboarding/domain/entities/onboarding_draft.dart';
import 'package:oma_app/features/onboarding/domain/entities/onboarding_step.dart';

import '../../helpers/fakes.dart';

OnboardingDraft _complete(String userId) => OnboardingDraft(
  userId: userId,
  fullName: 'Rania',
  birthdate: DateTime(1998, 4, 2),
  genderId: 'g1',
  showMeOptionId: 's1',
  bio: 'Diver and part-time barista.',
  lookingForIds: const ['lf1'],
  heightCm: 165,
  weightKg: 55,
  hobbyIds: const ['h1'],
  photos: const [
    DraftPhoto(
      localPath: '/tmp/a.jpg',
      photoId: 'p1',
      status: DraftPhotoStatus.uploaded,
    ),
  ],
  location: const DraftLocation(
    latitude: -6.26,
    longitude: 106.81,
    source: LocationSource.gps,
  ),
  notificationsDecided: true,
  submitKey: 'key-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnboardingDraft', () {
    test('resumes at the first unfinished step', () {
      const empty = OnboardingDraft(userId: 'u1');
      expect(empty.firstUnfinished, OnboardingStep.basics);

      final full = _complete('u1');
      expect(full.firstUnfinished, OnboardingStep.setup);
      expect(
        full.copyWith(bio: const Nullable(null)).firstUnfinished,
        OnboardingStep.about,
      );
      expect(
        full.copyWith(hobbyIds: const []).firstUnfinished,
        OnboardingStep.personality,
      );
      expect(
        full
            .copyWith(photos: const [DraftPhoto(localPath: '/tmp/a.jpg')])
            .firstUnfinished,
        OnboardingStep.photos,
      );
      expect(
        full.copyWith(location: const Nullable(null)).firstUnfinished,
        OnboardingStep.location,
      );
      expect(
        full.copyWith(notificationsDecided: false).firstUnfinished,
        OnboardingStep.notifications,
      );
    });

    test('basics needs a 2 to 100 character name', () {
      final d = _complete('u1');
      expect(d.copyWith(fullName: const Nullable(' R ')).basicsDone, isFalse);
      expect(d.copyWith(fullName: Nullable('R' * 101)).basicsDone, isFalse);
    });

    test('height and weight bounds follow the BE field table', () {
      final d = _complete('u1');
      expect(d.copyWith(heightCm: const Nullable(99)).aboutDone, isFalse);
      expect(d.copyWith(heightCm: const Nullable(251)).aboutDone, isFalse);
      expect(d.copyWith(weightKg: const Nullable(24)).aboutDone, isFalse);
      expect(d.copyWith(weightKg: const Nullable(301)).aboutDone, isFalse);
    });

    test('JSON round trip keeps every answer', () {
      final d = _complete('u1').copyWith(
        pronounId: const Nullable('pr1'),
        universityId: const Nullable('uni1'),
        universityName: const Nullable('Universitas Indonesia'),
        ambition: const Nullable('Open a dive school'),
        religionId: const Nullable('r1'),
        personalityTypeId: const Nullable('INFJ'),
      );
      final back = OnboardingDraft.fromJson(d.toJson());
      expect(back.toJson(), d.toJson());
      expect(back.birthdate, DateTime(1998, 4, 2));
      expect(d.toJson()['birthdate'], '1998-04-02');
    });

    test('toString never prints answers', () {
      final s = _complete('u1').toString();
      expect(s, isNot(contains('Rania')));
      expect(s, isNot(contains('1998')));
      expect(s, isNot(contains('-6.26')));
    });
  });

  group('OnboardingDraftController', () {
    late FakeAuthRepository auth;
    late MemoryDraftStore store;

    ProviderContainer create() {
      final c = ProviderContainer(
        overrides: baseOverrides(
          auth: auth,
          accounts: FakeAccountRepository(account()),
          drafts: store,
        ),
      );
      addTearDown(c.dispose);
      c.listen(onboardingDraftProvider, (_, _) {});
      c.listen(onboardingResumePathProvider, (_, _) {});
      return c;
    }

    setUp(() {
      auth = FakeAuthRepository(testUser);
      store = MemoryDraftStore();
    });

    test('edit saves to storage before updating state', () async {
      final c = create();
      await c.read(sessionControllerProvider.future);
      await c.read(onboardingDraftProvider.future);
      await c
          .read(onboardingDraftProvider.notifier)
          .edit((d) => d.copyWith(fullName: const Nullable('Rania')));
      expect(store.saved?.fullName, 'Rania');
      expect(c.read(onboardingDraftProvider).value?.fullName, 'Rania');
    });

    test('a restart restores answers and resumes the right step', () async {
      store.saved = _complete(
        'u1',
      ).copyWith(location: const Nullable(null), notificationsDecided: false);
      final c = create();
      await c.read(sessionControllerProvider.future);
      final draft = await c.read(onboardingDraftProvider.future);
      expect(draft?.fullName, 'Rania');
      expect(c.read(onboardingResumePathProvider), '/onboarding/location');
    });

    test('resume path is null while the draft loads', () async {
      final c = create();
      expect(c.read(onboardingResumePathProvider), isNull);
      await c.read(sessionControllerProvider.future);
      await c.read(onboardingDraftProvider.future);
      expect(c.read(onboardingResumePathProvider), '/onboarding/basics');
    });

    test("another account's draft is discarded", () async {
      store.saved = _complete('someone-else');
      final c = create();
      await c.read(sessionControllerProvider.future);
      final draft = await c.read(onboardingDraftProvider.future);
      expect(draft?.userId, 'u1');
      expect(draft?.fullName, isNull);
      expect(store.saved, isNull);
    });

    test('clear empties storage and keeps the owner', () async {
      store.saved = _complete('u1');
      final c = create();
      await c.read(sessionControllerProvider.future);
      await c.read(onboardingDraftProvider.future);
      await c.read(onboardingDraftProvider.notifier).clear();
      expect(store.saved, isNull);
      final d = c.read(onboardingDraftProvider).value;
      expect(d?.userId, 'u1');
      expect(d?.firstUnfinished, OnboardingStep.basics);
    });

    test('sign-out clears the draft', () async {
      store.saved = _complete('u1');
      final c = create();
      await c.read(sessionControllerProvider.future);
      await c.read(onboardingDraftProvider.future);
      await c.read(sessionControllerProvider.notifier).signOut();
      await pumpEventQueue();
      expect(store.saved, isNull);
      expect(c.read(onboardingDraftProvider).value, isNull);
    });

    test('signing in as another user loads a fresh draft', () async {
      store.saved = _complete('u1');
      final c = create();
      await c.read(sessionControllerProvider.future);
      await c.read(onboardingDraftProvider.future);
      auth.emit(const AuthSession(userId: 'u2', email: 'b@example.com'));
      await pumpEventQueue();
      final d = await c.read(onboardingDraftProvider.future);
      expect(d?.userId, 'u2');
      expect(d?.fullName, isNull);
    });
  });
}
