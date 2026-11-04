import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../core/errors/failure.dart';
import '../../photos/application/photo_providers.dart';
import '../../photos/application/photo_scanner_provider.dart';
import '../../photos/domain/photo_scanner.dart';
import '../../photos/domain/photo_upload.dart';
import '../domain/entities/onboarding_draft.dart';
import 'onboarding_draft_controller.dart';

const maxPhotos = 6;

enum TileStatus { checking, checkFailed, rejected, uploading, uploaded, failed }

@immutable
class PhotoTile {
  const PhotoTile({
    required this.key,
    required this.status,
    this.localPath,
    this.photoId,
    this.reason,
    this.inDraft = false,
  });

  final String key;
  final TileStatus status;
  final String? localPath;
  final String? photoId;
  final PhotoRejectReason? reason;

  final bool inDraft;
}

@immutable
class PhotoGridState {
  const PhotoGridState({
    this.extras = const [],
    this.uploading = const {},
    this.thumbs = const {},
    this.error,
  });

  final List<PhotoTile> extras;

  final Set<String> uploading;

  final Map<String, Uint8List> thumbs;

  final Failure? error;

  PhotoGridState copyWith({
    List<PhotoTile>? extras,
    Set<String>? uploading,
    Map<String, Uint8List>? thumbs,
    Failure? error,
    bool clearError = false,
  }) => PhotoGridState(
    extras: extras ?? this.extras,
    uploading: uploading ?? this.uploading,
    thumbs: thumbs ?? this.thumbs,
    error: clearError ? null : error ?? this.error,
  );

  List<PhotoTile> tiles(OnboardingDraft draft) => [
    for (final p in draft.photos)
      PhotoTile(
        key: p.localPath,
        localPath: p.localPath,
        photoId: p.photoId,
        inDraft: true,
        status: uploading.contains(p.localPath)
            ? TileStatus.uploading
            : p.isUploaded
            ? TileStatus.uploaded
            : TileStatus.failed,
      ),
    ...extras,
  ];

  int freeSlots(OnboardingDraft draft) =>
      maxPhotos - draft.photos.length - extras.length;
}

class PhotoGridController extends Notifier<PhotoGridState> {
  /// Upload tokens, in memory only (BE doc: never persisted).
  final _slots = <String, UploadSlot>{};

  @override
  PhotoGridState build() => const PhotoGridState();

  OnboardingDraftController get _draft =>
      ref.read(onboardingDraftProvider.notifier);
  OnboardingDraft? get _current => ref.read(onboardingDraftProvider).value;

  Future<void> prepare() async {
    try {
      await ref.read(photoScannerProvider).prepare();
    } on Object {
      // Surfaced on the first scan instead (fails closed there).
    }
  }

  void dismissError() => state = state.copyWith(clearError: true);

  Future<void> add() async {
    final draft = _current;
    if (draft == null) return;
    final free = state.freeSlots(draft);
    if (free <= 0) return;
    final List<String> picked;
    try {
      picked = await ref.read(photoPickerProvider).pick(max: free);
    } on Object {
      state = state.copyWith(error: const DeviceFailure('picker'));
      return;
    }
    for (final src in picked.take(free)) {
      await _process(src);
    }
  }

  Future<void> replace(String key) async {
    await remove(key);
    await add();
  }

  Future<void> retry(String key) async {
    final extra = state.extras.where((t) => t.key == key).firstOrNull;
    if (extra != null && extra.status == TileStatus.checkFailed) {
      _dropExtra(key);
      return _check(extra.localPath!);
    }
    final photo = _current?.photos.where((p) => p.localPath == key).firstOrNull;
    if (photo == null) return;
    if (!File(photo.localPath).existsSync()) return replace(key);
    await _upload(photo.localPath);
  }

  Future<void> _process(String source) async {
    _putExtra(PhotoTile(key: source, status: TileStatus.checking));
    final String compressed;
    try {
      compressed = await ref.read(photoCompressorProvider).compress(source);
    } on Object {
      _dropExtra(source);
      state = state.copyWith(error: const DeviceFailure('compress'));
      return;
    }
    _dropExtra(source);
    await _check(compressed);
  }

  Future<void> _check(String path) async {
    _putExtra(
      PhotoTile(key: path, localPath: path, status: TileStatus.checking),
    );
    final PhotoVerdict verdict;
    try {
      verdict = await ref.read(photoScannerProvider).scan(path);
    } on Object {
      _putExtra(
        PhotoTile(key: path, localPath: path, status: TileStatus.checkFailed),
      );
      return;
    }
    switch (verdict) {
      case PhotoRejected(:final reason):
        _putExtra(
          PhotoTile(
            key: path,
            localPath: path,
            status: TileStatus.rejected,
            reason: reason,
          ),
        );
      case PhotoAllowed():
        _dropExtra(path);
        await _draft.edit(
          (d) => d.copyWith(
            photos: [
              ...d.photos,
              DraftPhoto(localPath: path),
            ],
          ),
        );
        await _upload(path);
    }
  }

  Future<void> _upload(String path) async {
    state = state.copyWith(uploading: {...state.uploading, path});
    try {
      final slot = await _slotFor(path);
      await _setPhoto(
        path,
        (p) => p.copyWith(
          photoId: Nullable(slot.photoId),
          status: DraftPhotoStatus.uploading,
        ),
      );
      final storage = ref.read(photoStorageProvider);
      try {
        await storage.upload(slot, path);
      } on ApiFailure {
        // Expired or rejected token: refresh once and try again.
        final fresh = await ref
            .read(photoRepositoryProvider)
            .refreshSlot(slot.photoId);
        _slots[path] = fresh;
        await storage.upload(fresh, path);
      }
      final bytes = await File(path).readAsBytes();
      state = state.copyWith(thumbs: {...state.thumbs, slot.photoId: bytes});
      await _setPhoto(
        path,
        (p) => p.copyWith(status: DraftPhotoStatus.uploaded),
      );
      _slots.remove(path);
      await _deleteFile(path);
    } on Object {
      await _setPhoto(path, (p) => p.copyWith(status: DraftPhotoStatus.failed));
    } finally {
      state = state.copyWith(uploading: {...state.uploading}..remove(path));
    }
  }

  /// Reuses the reserved photo_id so a retry never reserves a second slot.
  Future<UploadSlot> _slotFor(String path) async {
    final repo = ref.read(photoRepositoryProvider);
    final cached = _slots[path];
    if (cached != null && cached.isUsableAt(DateTime.now())) return cached;
    final existing = _current?.photos
        .where((p) => p.localPath == path)
        .firstOrNull
        ?.photoId;
    final slot = existing != null
        ? await repo.refreshSlot(existing)
        : (await repo.reserve([
            PhotoFileMeta(
              filename: path.split('/').last,
              contentType: 'image/jpeg',
              fileSize: await File(path).length(),
            ),
          ])).single;
    return _slots[path] = slot;
  }

  Future<void> remove(String key) async {
    final extra = state.extras.where((t) => t.key == key).firstOrNull;
    if (extra != null) {
      _dropExtra(key);
      if (extra.localPath != null) await _deleteFile(extra.localPath!);
      return;
    }
    final photo = _current?.photos.where((p) => p.localPath == key).firstOrNull;
    if (photo == null) return;
    if (photo.photoId != null) {
      try {
        await ref.read(photoRepositoryProvider).delete(photo.photoId!);
      } on Failure catch (e) {
        state = state.copyWith(error: e);
        return;
      }
    }
    _slots.remove(key);
    await _deleteFile(key);
    await _draft.edit(
      (d) => d.copyWith(
        photos: [
          for (final p in d.photos)
            if (p.localPath != key) p,
        ],
      ),
    );
  }

  Future<void> move(String key, int to) => _draft.edit((d) {
    final photos = [...d.photos];
    final from = photos.indexWhere((p) => p.localPath == key);
    if (from < 0) return d;
    final p = photos.removeAt(from);
    photos.insert(to.clamp(0, photos.length), p);
    return d.copyWith(photos: photos);
  });

  Future<void> makeMain(String key) => move(key, 0);

  Future<void> _setPhoto(String path, DraftPhoto Function(DraftPhoto) f) =>
      _draft.edit(
        (d) => d.copyWith(
          photos: [for (final p in d.photos) p.localPath == path ? f(p) : p],
        ),
      );

  void _putExtra(PhotoTile tile) {
    final extras = [...state.extras];
    final i = extras.indexWhere((t) => t.key == tile.key);
    i < 0 ? extras.add(tile) : extras[i] = tile;
    state = state.copyWith(extras: extras);
  }

  void _dropExtra(String key) => state = state.copyWith(
    extras: [
      for (final t in state.extras)
        if (t.key != key) t,
    ],
  );

  Future<void> _deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on FileSystemException {
      // The OS may already have cleared the temp folder.
    }
  }
}

/// Kept alive so an upload finishes even if the user goes back a step.
final photoGridProvider = NotifierProvider<PhotoGridController, PhotoGridState>(
  PhotoGridController.new,
);
