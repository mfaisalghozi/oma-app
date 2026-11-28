import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../domain/entities/deck_card.dart';

/// One person, drawn from the board: photo, segments, name, distance, ambition,
/// tags. No area, no "super liked you" badge, no balance chip (section 16).
class ProfileCard extends StatefulWidget {
  const ProfileCard({required this.card, super.key});

  final DeckCard card;

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  int _photo = 0;

  void _step(int delta) {
    final count = widget.card.photos.length;
    if (count < 2) return;
    setState(() => _photo = (_photo + delta + count) % count);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final card = widget.card;
    final photo = card.photos.isEmpty
        ? null
        : card.photos[_photo.clamp(0, card.photos.length - 1)];
    return Semantics(
      label:
          '${card.displayName}, ${card.age}, ${card.distanceLabel}'
          '${card.ambition == null ? '' : '. ${card.ambition}'}',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          color: c.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Photo(url: photo?.readUrl, initial: card.displayName),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: _Segments(
                        count: card.photos.length,
                        current: _photo,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 90,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.28),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _step(-1),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _step(1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            '${card.displayName}, ${card.age}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: c.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          card.distanceLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.textMuted,
                          ),
                        ),
                      ],
                    ),
                    if (card.ambition case final ambition?) ...[
                      const SizedBox(height: 6),
                      Text(
                        ambition,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: c.textMuted,
                        ),
                      ),
                    ],
                    if (card.tags.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in card.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: c.tag,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: c.onTag,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url, required this.initial});

  final String? url;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.mint, c.card],
        ),
      ),
      child: Center(
        child: Text(
          initial.isEmpty ? '?' : initial.characters.first,
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w800,
            color: c.primaryStrong.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();
    final c = context.oma;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          for (var index = 0; index < count; index++)
            Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: index == count - 1 ? 0 : 4),
                decoration: BoxDecoration(
                  color: index == current
                      ? c.background
                      : c.background.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
