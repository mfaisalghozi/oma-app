import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/auth/application/session_controller.dart';
import 'package:oma_app/features/auth/domain/entities/account_state.dart';
import 'package:oma_app/features/onboarding/application/onboarding_draft_controller.dart';
import 'package:oma_app/features/onboarding/application/onboarding_submit_controller.dart';
import 'package:oma_app/features/onboarding/domain/entities/onboarding_draft.dart';
import 'package:oma_app/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:oma_app/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:oma_app/features/onboarding/domain/usecases/onboarding_payload.dart';
import 'package:oma_app/features/onboarding/presentation/profile_setup_screen.dart';
import 'package:oma_app/features/photos/application/photo_providers.dart';
import 'package:oma_app/features/photos/domain/photo_upload.dart';

import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

OnboardingDraft _complete({List<DraftPhoto>? photos}) => OnboardingDraft(
  userId: 'u1',
  fullName: ' Rania ',
  birthdate: DateTime(1998, 4, 2),
  genderId: 'g-w',
  showMeOptionId: 's-m',
  bio: 'Diver.',
  lookingForIds: const ['lf-1'],
  heightCm: 165,
  weightKg: 55,
  ambition: '  ',
  religionId: 'r-1',
  hobbyIds: const ['h-1', 'h-2'],
  photos:
      photos ??
      const [
        DraftPhoto(
          localPath: '/a',
          photoId: 'p-a',
          status: DraftPhotoStatus.uploaded,
        ),
        DraftPhoto(
          localPath: '/b',
          photoId: 'p-b',
          status: DraftPhotoStatus.uploaded,
        ),
      ],
  location: const DraftLocation(
    latitude: -6.26,
    longitude: 106.81,
    source: LocationSource.gps,
  ),
  notificationsDecided: true,
);

class FakeOnboardingRepo implements OnboardingRepository {
  final keys = <String>[];
  final payloads = <Map<String, Object?>>[];
  final failures = <Object>[];
  Completer<void>? hold;

  @override
  Future<void> submit(
    Map<String, Object?> payload, {
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    payloads.add(payload);
    if (hold != null) await hold!.future;
    if (failures.isNotEmpty) throw failures.removeAt(0);
  }
}

class OkPhotoRepo implements PhotoRepository {
  int refreshes = 0;

  @override
  Future<List<UploadSlot>> reserve(List<PhotoFileMeta> files) async =>
      throw UnimplementedError();

  @override
  Future<UploadSlot> refreshSlot(String photoId) async {
    refreshes++;
    return UploadSlot(
      photoId: photoId,
      bucket: 'b',
      path: 'p',
      uploadToken: 't',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> delete(String photoId) async {}

  @override
  Future<Map<String, String>> signedUrls() async => const {};
}

class OkStorage implements PhotoStorage {
  int uploads = 0;

  @override
  Future<void> upload(UploadSlot slot, String filePath) async => uploads++;
}

class FakePicker implements PhotoPicker {
  int calls = 0;

  @override
  Future<List<String>> pick({required int max}) async {
    calls++;
    return const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onboardingPayload', () {
    test('matches the BE §8.6 shape, omits empty optionals', () {
      final p = onboardingPayload(
        _complete(
          photos: const [
            DraftPhoto(
              localPath: '/a',
              photoId: 'p-a',
              status: DraftPhotoStatus.uploaded,
            ),
            DraftPhoto(localPath: '/x', photoId: 'p-x'),
            DraftPhoto(
              localPath: '/b',
              photoId: 'p-b',
              status: DraftPhotoStatus.uploaded,
            ),
          ],
        ),
      );
      expect(p['profile'], {
        'full_name': 'Rania',
        'birthdate': '1998-04-02',
        'gender_id': 'g-w',
        'show_me_option_id': 's-m',
        'bio': 'Diver.',
        'height_cm': 165,
        'weight_kg': 55,
        'religion_id': 'r-1',
      });
      expect(p['looking_for_ids'], ['lf-1']);
      expect(p['hobby_ids'], ['h-1', 'h-2']);
      expect(p['photos'], [
        {'photo_id': 'p-a', 'position': 1},
        {'photo_id': 'p-b', 'position': 2},
      ]);
      expect(p['location'], {'latitude': -6.26, 'longitude': 106.81});
    });

    test('422 fields map to the step that owns them', () {
      expect(stepForField('profile.full_name'), OnboardingStep.basics);
      expect(stepForField('height_cm'), OnboardingStep.about);
      expect(stepForField('hobby_ids[0]'), OnboardingStep.personality);
      expect(stepForField('photos[1].photo_id'), OnboardingStep.photos);
      expect(stepForField('location.latitude'), OnboardingStep.location);
      expect(stepForField('something_new'), OnboardingStep.basics);
    });
  });

  group('OnboardingSubmitController', () {
    late MemoryDraftStore store;
    late FakeAccountRepository accounts;
    late FakeOnboardingRepo repo;
    late OkStorage storage;
    late OkPhotoRepo photos;
    late FakePicker picker;

    setUp(() {
      store = MemoryDraftStore(_complete());
      accounts = FakeAccountRepository(account());
      repo = FakeOnboardingRepo();
      storage = OkStorage();
      photos = OkPhotoRepo();
      picker = FakePicker();
    });

    List<Override> overrides() => [
      ...baseOverrides(
        auth: FakeAuthRepository(testUser),
        accounts: accounts,
        drafts: store,
      ),
      onboardingRepositoryProvider.overrideWithValue(repo),
      photoRepositoryProvider.overrideWithValue(photos),
      photoStorageProvider.overrideWithValue(storage),
      photoPickerProvider.overrideWithValue(picker),
    ];

    Future<ProviderContainer> create() async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      c
        ..listen(onboardingDraftProvider, (_, _) {})
        ..listen(onboardingSubmitProvider, (_, _) {});
      await c.read(sessionControllerProvider.future);
      await c.read(onboardingDraftProvider.future);
      return c;
    }

    test('success clears the draft and opens Discover', () async {
      final c = await create();
      accounts.result = account(next: NextAction.discovery);
      await c.read(onboardingSubmitProvider.notifier).submit();

      expect(c.read(onboardingSubmitProvider), isA<SubmitDone>());
      expect(repo.keys, hasLength(1));
      expect(store.saved, isNull);
      final s = c.read(sessionControllerProvider).value! as SignedIn;
      expect(s.account.nextAction, NextAction.discovery);
    });

    test(
      'offline during M11b, then Try again succeeds with the same key',
      () async {
        final c = await create();
        repo.failures.add(const NetworkFailure());
        await c.read(onboardingSubmitProvider.notifier).submit();

        final failed = c.read(onboardingSubmitProvider);
        expect(failed, isA<SubmitFailed>());
        expect((failed as SubmitFailed).phase, SetupPhase.saving);
        expect(store.saved?.fullName, ' Rania ', reason: 'draft kept');
        final key = store.saved!.submitKey;
        expect(key, isNotNull);

        accounts.result = account(next: NextAction.discovery);
        await c.read(onboardingSubmitProvider.notifier).submit();
        expect(c.read(onboardingSubmitProvider), isA<SubmitDone>());
        expect(repo.keys, [key, key], reason: 'no duplicate profile');
        expect(store.saved, isNull);
      },
    );

    test('409 already completed counts as success', () async {
      final c = await create();
      repo.failures.add(
        const ApiFailure(
          code: ApiErrorCode.onboardingAlreadyCompleted,
          statusCode: 409,
        ),
      );
      await c.read(onboardingSubmitProvider.notifier).submit();
      expect(c.read(onboardingSubmitProvider), isA<SubmitDone>());
      expect(store.saved, isNull);
    });

    test('422 sends the user to the owning step, draft kept', () async {
      final c = await create();
      repo.failures.add(
        const ApiFailure(
          code: ApiErrorCode.onboardingValidationFailed,
          statusCode: 422,
          details: [
            {'field': 'hobby_ids', 'reason': 'invalid'},
            {'field': 'height_cm', 'reason': 'out_of_range'},
          ],
        ),
      );
      await c.read(onboardingSubmitProvider.notifier).submit();
      final s = c.read(onboardingSubmitProvider);
      expect(s, isA<SubmitNeedsFix>());
      expect((s as SubmitNeedsFix).step, OnboardingStep.about);
      expect(store.saved?.heightCm, 165);
    });

    test('5xx opens M11c', () async {
      final c = await create();
      repo.failures.add(
        const ApiFailure(
          code: ApiErrorCode.internalServerError,
          statusCode: 500,
        ),
      );
      await c.read(onboardingSubmitProvider.notifier).submit();
      expect(c.read(onboardingSubmitProvider), isA<SubmitFailed>());
      expect(store.saved, isNotNull);
    });

    test('pending photo uploads are retried before submit', () async {
      final dir = await Directory.systemTemp.createTemp('oma_submit');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/b.jpg')..writeAsBytesSync([1, 2, 3]);
      store.saved = _complete(
        photos: [
          const DraftPhoto(
            localPath: '/a',
            photoId: 'p-a',
            status: DraftPhotoStatus.uploaded,
          ),
          DraftPhoto(
            localPath: file.path,
            photoId: 'p-b',
            status: DraftPhotoStatus.failed,
          ),
        ],
      );
      final c = await create();
      await c.read(onboardingSubmitProvider.notifier).submit();
      expect(storage.uploads, 1);
      expect(photos.refreshes, 1, reason: 'same photo_id, fresh token');
      expect(repo.payloads.single['photos'], [
        {'photo_id': 'p-a', 'position': 1},
        {'photo_id': 'p-b', 'position': 2},
      ]);
    });

    test('a missing photo file sends the user back to M09', () async {
      store.saved = _complete(
        photos: const [
          DraftPhoto(
            localPath: '/gone.jpg',
            photoId: 'p-b',
            status: DraftPhotoStatus.failed,
          ),
        ],
      );
      final c = await create();
      await c.read(onboardingSubmitProvider.notifier).submit();

      final s = c.read(onboardingSubmitProvider);
      expect(s, isA<SubmitNeedsFix>());
      expect((s as SubmitNeedsFix).step, OnboardingStep.photos);
      expect(picker.calls, 0, reason: 'submit must not open the gallery');
      expect(repo.payloads, isEmpty);
      expect(store.saved, isNotNull);
    });

    test('a draft without photos is not submitted', () async {
      store.saved = _complete(photos: const []);
      final c = await create();
      await c.read(onboardingSubmitProvider.notifier).submit();

      final s = c.read(onboardingSubmitProvider);
      expect(s, isA<SubmitNeedsFix>());
      expect((s as SubmitNeedsFix).step, OnboardingStep.photos);
      expect(picker.calls, 0);
      expect(repo.payloads, isEmpty);
    });
  });

  group('M11b / M11c screen', () {
    late FakeOnboardingRepo repo;

    setUp(() => repo = FakeOnboardingRepo());

    List<Override> overrides() => [
      ...baseOverrides(
        auth: FakeAuthRepository(testUser),
        accounts: FakeAccountRepository(account()),
        drafts: MemoryDraftStore(_complete()),
      ),
      onboardingRepositoryProvider.overrideWithValue(repo),
    ];

    goldenBothThemes('m11b_profile_setup', (tester, theme) async {
      repo.hold = Completer();
      addTearDown(() => repo.hold!.complete());
      await pumpScreen(
        tester,
        const ProfileSetupScreen(),
        theme: theme,
        overrides: overrides(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Setting up your profile'), findsOneWidget);
    });

    goldenBothThemes('m11c_profile_setup_failed', (tester, theme) async {
      repo.failures.add(const NetworkFailure());
      await pumpScreen(
        tester,
        const ProfileSetupScreen(),
        theme: theme,
        overrides: overrides(),
      );
      await tester.pumpAndSettle();
      expect(find.text("We couldn't finish your profile"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
