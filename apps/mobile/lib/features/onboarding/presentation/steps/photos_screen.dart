import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/oma_colors.dart';
import '../../../../core/widgets/oma_banner.dart';
import '../../../photos/application/photo_providers.dart';
import '../../../photos/domain/photo_scanner.dart';
import '../../application/onboarding_draft_controller.dart';
import '../../application/photo_grid_controller.dart';
import '../../domain/entities/onboarding_step.dart';
import '../widgets/draft_builder.dart';
import '../widgets/step_frame.dart';

/// Draws a tile's image. Overridden in golden tests.
final photoThumbBuilderProvider = Provider<Widget Function(PhotoTile tile)>(
  (ref) =>
      (tile) => PhotoThumb(tile: tile),
);

/// M09 Add your photos: up to 6, first is Main, hold and drag to reorder.
class PhotosScreen extends StatelessWidget {
  const PhotosScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      DraftBuilder(builder: (_, draft) => const _PhotosBody());
}

class _PhotosBody extends ConsumerStatefulWidget {
  const _PhotosBody();

  @override
  ConsumerState<_PhotosBody> createState() => _PhotosBodyState();
}

class _PhotosBodyState extends ConsumerState<_PhotosBody> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(photoGridProvider.notifier).prepare());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final draft = ref.watch(onboardingDraftProvider).value!;
    final grid = ref.watch(photoGridProvider);
    final ctrl = ref.read(photoGridProvider.notifier);
    final tiles = grid.tiles(draft);
    final free = grid.freeSlots(draft);
    final rejected = [
      for (var i = 0; i < tiles.length; i++)
        if (tiles[i].status == TileStatus.rejected) (i + 1, tiles[i].reason),
    ];

    return StepFrame(
      step: OnboardingStep.photos,
      title: 'Add your photos',
      subtitle:
          'Up to 6. Hold and drag to reorder; the first is your main photo.',
      canContinue: draft.photosDone,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 3 / 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < tiles.length; i++)
                _DraggableTile(index: i, tile: tiles[i]),
              for (var i = 0; i < free; i++)
                _AddTile(enabled: i == 0, onTap: ctrl.add),
            ],
          ),
          const SizedBox(height: 16),
          for (final (n, reason) in rejected) ...[
            OmaBanner(message: _rejectedText(n, reason)),
            const SizedBox(height: 8),
          ],
          if (grid.error != null) ...[
            OmaBanner(
              message: _errorText(grid.error!),
              actionLabel: 'OK',
              onAction: ctrl.dismissError,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'You need at least 1 approved photo to show up in Discover.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }

  static String _rejectedText(int n, PhotoRejectReason? reason) =>
      'Photo $n was not approved: it shows '
      '${reason == PhotoRejectReason.explicitNudity ? 'explicit nudity' : 'nudity'}. '
      'Only clear photos of you, please.';

  static String _errorText(Object e) => switch (e) {
    NetworkFailure() => "You're offline. Try again when you're back.",
    _ => "Something went wrong with that photo. Please try again.",
  };
}

class _DraggableTile extends ConsumerWidget {
  const _DraggableTile({required this.index, required this.tile});

  final int index;
  final PhotoTile tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(photoGridProvider.notifier);
    final child = _Tile(index: index, tile: tile);
    if (!tile.inDraft) return child;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != tile.key,
      onAcceptWithDetails: (d) => ctrl.move(d.data, index),
      builder: (context, candidates, _) => LongPressDraggable<String>(
        data: tile.key,
        feedback: SizedBox(
          width: 110,
          height: 146,
          child: Opacity(opacity: 0.85, child: child),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: child),
        child: AnimatedScale(
          scale: candidates.isEmpty ? 1 : 0.94,
          duration: const Duration(milliseconds: 120),
          child: child,
        ),
      ),
    );
  }
}

/// Same dark scrim in both themes so white labels stay readable on photos.
const _scrim = Color(0x990B1F33);

class _Tile extends ConsumerWidget {
  const _Tile({required this.index, required this.tile});

  final int index;
  final PhotoTile tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.oma;
    final ctrl = ref.read(photoGridProvider.notifier);
    final thumb = ref.watch(photoThumbBuilderProvider)(tile);
    final busy =
        tile.status == TileStatus.checking ||
        tile.status == TileStatus.uploading;

    Widget overlay(String label, {String? action, VoidCallback? onAction}) =>
        Container(
          color: _scrim,
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: 32,
                  child: FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF10303A),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    child: Text(action),
                  ),
                ),
              ],
            ],
          ),
        );

    return Semantics(
      label: 'Photo ${index + 1}',
      value: tile.status.name,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: c.card,
          child: InkWell(
            onTap: tile.status == TileStatus.uploaded
                ? () => _menu(context, ctrl)
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                thumb,
                if (busy)
                  overlay(
                    tile.status == TileStatus.checking
                        ? 'Checking'
                        : 'Uploading',
                  ),
                if (busy)
                  const Align(
                    alignment: Alignment(0, 0.45),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (tile.status == TileStatus.rejected)
                  overlay(
                    'Not approved',
                    action: 'Replace',
                    onAction: () => ctrl.replace(tile.key),
                  ),
                if (tile.status == TileStatus.failed)
                  overlay(
                    "Didn't upload",
                    action: 'Retry',
                    onAction: () => ctrl.retry(tile.key),
                  ),
                if (tile.status == TileStatus.checkFailed)
                  overlay(
                    "Couldn't check",
                    action: 'Try again',
                    onAction: () => ctrl.retry(tile.key),
                  ),
                if (index == 0 && tile.inDraft)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.primary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'Main',
                        style: TextStyle(
                          color: c.onPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                if (!busy && tile.status != TileStatus.uploaded)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: IconButton(
                      tooltip: 'Remove photo',
                      iconSize: 18,
                      color: Colors.white,
                      onPressed: () => ctrl.remove(tile.key),
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, PhotoGridController ctrl) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index != 0)
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: const Text('Make main photo'),
                  onTap: () {
                    Navigator.pop(sheet);
                    ctrl.makeMain(tile.key);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.pop(sheet);
                  ctrl.remove(tile.key);
                },
              ),
            ],
          ),
        ),
      );
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Semantics(
      button: true,
      label: 'Add photo',
      enabled: enabled,
      excludeSemantics: true,
      child: Material(
        color: c.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.border, width: 1.5),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onTap: enabled ? onTap : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add,
                color: enabled ? c.primary : c.textMuted,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                'Add',
                style: TextStyle(
                  color: enabled ? c.primary : c.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The photo itself: memory bytes after upload, the local file before, or
/// the signed URL after a restart.
class PhotoThumb extends ConsumerWidget {
  const PhotoThumb({required this.tile, super.key});

  final PhotoTile tile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.oma;
    final bytes = tile.photoId == null
        ? null
        : ref.watch(photoGridProvider.select((s) => s.thumbs[tile.photoId]));
    if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover);
    final path = tile.localPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    if (tile.photoId != null) {
      final url = ref.watch(photoSignedUrlsProvider).value?[tile.photoId];
      if (url != null) return Image.network(url, fit: BoxFit.cover);
    }
    return Icon(Icons.image_outlined, color: c.textMuted);
  }
}
