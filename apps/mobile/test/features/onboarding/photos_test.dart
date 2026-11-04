import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/auth/application/session_controller.dart';
import 'package:oma_app/features/onboarding/application/onboarding_draft_controller.dart';
import 'package:oma_app/features/onboarding/application/photo_grid_controller.dart';
import 'package:oma_app/features/onboarding/domain/entities/onboarding_draft.dart';
import 'package:oma_app/features/onboarding/presentation/steps/photos_screen.dart';
import 'package:oma_app/features/photos/application/photo_providers.dart';
import 'package:oma_app/features/photos/application/photo_scanner_provider.dart';
import 'package:oma_app/features/photos/domain/photo_scanner.dart';
import 'package:oma_app/features/photos/domain/photo_upload.dart';

import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

late Directory _tmp;
int _n = 0;

String _file(String name) {
  final f = File('${_tmp.path}/${_n++}_$name.jpg')..writeAsBytesSync([1, 2, 3]);
  return f.path;
}

class FakePicker implements PhotoPicker {
  List<String> next = [];
  int? lastMax;

  @override
  Future<List<String>> pick({required int max}) async {
    lastMax = max;
    return next;
  }
}

class CopyCompressor implements PhotoCompressor {
  @override
  Future<String> compress(String sourcePath) async {
    final name = sourcePath.split('/').last.replaceAll('.jpg', '');
    return _file('c_$name');
  }
}

/// "nude" in the name is rejected, "broken" throws.
class FakeScanner implements PhotoScanner {
  bool failNext = false;

  @override
  Future<void> prepare() async {}

  @override
  Future<PhotoVerdict> scan(String filePath) async {
    if (failNext) {
      failNext = false;
      throw const DeviceFailure('scan');
    }
    if (filePath.contains('nude')) {
      return const PhotoRejected(PhotoRejectReason.nudity);
    }
    return const PhotoAllowed();
  }
}

class FakePhotoRepo implements PhotoRepository {
  int reserves = 0;
  int refreshes = 0;
  final deleted = <String>[];

  UploadSlot _slot(String id) => UploadSlot(
    photoId: id,
    bucket: 'profile-photos',
    path: 'u1/$id.jpg',
    uploadToken: 'tok-$id-$refreshes',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );

  @override
  Future<List<UploadSlot>> reserve(List<PhotoFileMeta> files) async => [
    for (final _ in files) _slot('p${++reserves}'),
  ];

  @override
  Future<UploadSlot> refreshSlot(String photoId) async {
    refreshes++;
    return _slot(photoId);
  }

  @override
  Future<void> delete(String photoId) async => deleted.add(photoId);

  @override
  Future<Map<String, String>> signedUrls() async => const {};
}

class FakeStorage implements PhotoStorage {
  final uploads = <String>[];

  /// Failures to throw before succeeding.
  final failures = <Object>[];
  Completer<void>? hold;

  @override
  Future<void> upload(UploadSlot slot, String filePath) async {
    if (hold != null) await hold!.future;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    uploads.add('${slot.photoId}:${slot.uploadToken}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryDraftStore store;
  late FakePicker picker;
  late FakeScanner scanner;
  late FakePhotoRepo repo;
  late FakeStorage storage;

  setUp(() async {
    _tmp = await Directory.systemTemp.createTemp('oma_photos');
    store = MemoryDraftStore();
    picker = FakePicker();
    scanner = FakeScanner();
    repo = FakePhotoRepo();
    storage = FakeStorage();
  });
  tearDown(() => _tmp.delete(recursive: true));

  List<Override> overrides() => [
    ...baseOverrides(
      auth: FakeAuthRepository(testUser),
      accounts: FakeAccountRepository(account()),
      drafts: store,
    ),
    photoPickerProvider.overrideWithValue(picker),
    photoCompressorProvider.overrideWithValue(CopyCompressor()),
    photoScannerProvider.overrideWithValue(scanner),
    photoRepositoryProvider.overrideWithValue(repo),
    photoStorageProvider.overrideWithValue(storage),
  ];

  Future<ProviderContainer> create() async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    c
      ..listen(onboardingDraftProvider, (_, _) {})
      ..listen(photoGridProvider, (_, _) {});
    await c.read(sessionControllerProvider.future);
    await c.read(onboardingDraftProvider.future);
    return c;
  }

  List<DraftPhoto> photos(ProviderContainer c) =>
      c.read(onboardingDraftProvider).value!.photos;

  group('PhotoGridController', () {
    test(
      'a clean photo is checked, reserved, uploaded, temp deleted',
      () async {
        final c = await create();
        picker.next = [_file('beach')];
        await c.read(photoGridProvider.notifier).add();

        final p = photos(c).single;
        expect(p.status, DraftPhotoStatus.uploaded);
        expect(p.photoId, 'p1');
        expect(storage.uploads, ['p1:tok-p1-0']);
        expect(File(p.localPath).existsSync(), isFalse);
        expect(c.read(photoGridProvider).thumbs['p1'], isNotNull);
        expect(c.read(onboardingDraftProvider).value!.photosDone, isTrue);
      },
    );

    test('a flagged photo never reaches the API', () async {
      final c = await create();
      picker.next = [_file('nude')];
      await c.read(photoGridProvider.notifier).add();

      expect(photos(c), isEmpty);
      expect(repo.reserves, 0);
      expect(storage.uploads, isEmpty);
      final tile = c.read(photoGridProvider).extras.single;
      expect(tile.status, TileStatus.rejected);
      expect(tile.reason, PhotoRejectReason.nudity);
    });

    test('Replace drops the rejected tile and picks again', () async {
      final c = await create();
      picker.next = [_file('nude')];
      await c.read(photoGridProvider.notifier).add();
      final key = c.read(photoGridProvider).extras.single.key;

      picker.next = [_file('clean')];
      await c.read(photoGridProvider.notifier).replace(key);
      expect(c.read(photoGridProvider).extras, isEmpty);
      expect(File(key).existsSync(), isFalse);
      expect(photos(c).single.isUploaded, isTrue);
    });

    test('a failed upload retries with the same photo_id', () async {
      final c = await create();
      storage.failures.add(const NetworkFailure());
      picker.next = [_file('a')];
      await c.read(photoGridProvider.notifier).add();
      expect(photos(c).single.status, DraftPhotoStatus.failed);
      expect(photos(c).single.photoId, 'p1');

      await c
          .read(photoGridProvider.notifier)
          .retry(photos(c).single.localPath);
      expect(photos(c).single.status, DraftPhotoStatus.uploaded);
      expect(repo.reserves, 1, reason: 'no second slot');
      expect(storage.uploads.single, startsWith('p1:'));
    });

    test('an expired token is refreshed and the upload retried', () async {
      final c = await create();
      storage.failures.add(
        const ApiFailure(code: 'STORAGE_UPLOAD_FAILED', statusCode: 400),
      );
      picker.next = [_file('a')];
      await c.read(photoGridProvider.notifier).add();
      expect(repo.refreshes, 1);
      expect(storage.uploads, ['p1:tok-p1-1']);
      expect(photos(c).single.isUploaded, isTrue);
    });

    test('a scan error fails closed with Try again', () async {
      final c = await create();
      scanner.failNext = true;
      picker.next = [_file('a')];
      await c.read(photoGridProvider.notifier).add();
      final tile = c.read(photoGridProvider).extras.single;
      expect(tile.status, TileStatus.checkFailed);
      expect(repo.reserves, 0);

      await c.read(photoGridProvider.notifier).retry(tile.key);
      expect(c.read(photoGridProvider).extras, isEmpty);
      expect(photos(c).single.isUploaded, isTrue);
    });

    test('picks are limited to the free slots', () async {
      final c = await create();
      picker.next = [for (var i = 0; i < 5; i++) _file('x$i')];
      await c.read(photoGridProvider.notifier).add();
      expect(picker.lastMax, 6);
      picker.next = [_file('y'), _file('z')];
      await c.read(photoGridProvider.notifier).add();
      expect(picker.lastMax, 1);
      expect(photos(c), hasLength(6));
      final draft = c.read(onboardingDraftProvider).value!;
      expect(c.read(photoGridProvider).freeSlots(draft), 0);
    });

    test('reorder and make main', () async {
      final c = await create();
      picker.next = [_file('a'), _file('b'), _file('c')];
      await c.read(photoGridProvider.notifier).add();
      final keys = photos(c).map((p) => p.localPath).toList();
      await c.read(photoGridProvider.notifier).makeMain(keys[2]);
      expect(photos(c).map((p) => p.localPath), [keys[2], keys[0], keys[1]]);
      await c.read(photoGridProvider.notifier).move(keys[2], 2);
      expect(photos(c).map((p) => p.localPath), keys);
    });

    test('remove deletes the reserved photo on the API', () async {
      final c = await create();
      picker.next = [_file('a')];
      await c.read(photoGridProvider.notifier).add();
      await c
          .read(photoGridProvider.notifier)
          .remove(photos(c).single.localPath);
      expect(repo.deleted, ['p1']);
      expect(photos(c), isEmpty);
    });
  });

  group('M09 screen', () {
    final colors = [
      const Color(0xFF7FB7BE),
      const Color(0xFFD9A07B),
      const Color(0xFF8C9A6E),
      const Color(0xFFB08EA2),
      const Color(0xFF6E8CA8),
      const Color(0xFFC9B37E),
    ];

    List<Override> screenOverrides() => [
      ...overrides(),
      photoThumbBuilderProvider.overrideWithValue(
        (tile) => ColoredBox(
          color:
              colors[tile.key
                      .split('/')
                      .last
                      .codeUnits
                      .fold(0, (a, b) => a + b) %
                  colors.length],
        ),
      ),
    ];

    Future<void> pump(WidgetTester tester, GoldenTheme theme) async {
      await pumpScreen(
        tester,
        const PhotosScreen(),
        theme: theme,
        overrides: screenOverrides(),
      );
      await tester.pumpAndSettle();
    }

    Future<void> addPhotos(WidgetTester tester, List<String> names) async {
      picker.next = [for (final n in names) _file(n)];
      await tester.runAsync(() async {
        await tester.tap(find.text('Add').first);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    }

    testWidgets('Next needs one uploaded photo', (tester) async {
      await pump(tester, GoldenTheme.lagoon);
      bool next() =>
          tester
              .widget<TextButton>(
                find.ancestor(
                  of: find.text('Next'),
                  matching: find.byType(TextButton),
                ),
              )
              .onPressed !=
          null;
      expect(next(), isFalse);
      await addPhotos(tester, ['a']);
      await tester.pumpAndSettle();
      expect(next(), isTrue);
      expect(find.text('Main'), findsOneWidget);
    });

    goldenBothThemes('m09_photos_empty', (tester, theme) async {
      await pump(tester, theme);
    });

    goldenBothThemes('m09_photos_uploading', (tester, theme) async {
      await pump(tester, theme);
      await addPhotos(tester, ['a', 'b']);
      storage.hold = Completer();
      await addPhotos(tester, ['c']);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Uploading'), findsOneWidget);
      addTearDown(() => storage.hold?.complete());
    });

    goldenBothThemes('m09_photos_failed', (tester, theme) async {
      await pump(tester, theme);
      await addPhotos(tester, ['a']);
      storage.failures.add(const NetworkFailure());
      await addPhotos(tester, ['b']);
      await tester.pumpAndSettle();
      expect(find.text("Didn't upload"), findsOneWidget);
    });

    goldenBothThemes('m09_photos_full', (tester, theme) async {
      await pump(tester, theme);
      await addPhotos(tester, ['a', 'b', 'c', 'nude', 'e', 'f']);
      await tester.pumpAndSettle();
      expect(find.text('Not approved'), findsOneWidget);
      expect(find.text('Add'), findsNothing);
      expect(
        find.text(
          'Photo 6 was not approved: it shows nudity. '
          'Only clear photos of you, please.',
        ),
        findsOneWidget,
      );
    });
  });
}
