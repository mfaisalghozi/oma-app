import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../domain/entities/deck_card.dart';
import '../../domain/entities/swipe_kind.dart';
import 'action_bar.dart';
import 'profile_card.dart';
import 'swipe_stamp.dart';

/// Hand-built card stack: one AnimationController, tilt 0.06° per pixel,
/// commit at 110 px or 0.6 px/ms, 300 ms fly-out. Only the top two cards are
/// built and each sits in its own RepaintBoundary.
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    required this.cards,
    required this.onSwipe,
    required this.onComment,
    this.enabled = true,
    super.key,
  });

  final List<DeckCard> cards;
  final Future<void> Function(SwipeKind kind) onSwipe;
  final VoidCallback onComment;
  final bool enabled;

  @override
  State<SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends State<SwipeDeck>
    with SingleTickerProviderStateMixin {
  static const _commitDistance = 110.0;
  static const _flingVelocity = 600.0;
  static const _tiltPerPixel = 0.06;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  Offset _drag = Offset.zero;
  Animation<Offset>? _fly;
  SwipeKind? _pending;
  bool _burst = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(SwipeKind kind) {
    if (!widget.enabled || _pending != null) return;
    final size = MediaQuery.sizeOf(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final end = switch (kind) {
      SwipeKind.like => Offset(size.width * 1.4, _drag.dy + 40),
      SwipeKind.pass => Offset(-size.width * 1.4, _drag.dy + 40),
      SwipeKind.superLike => Offset(_drag.dx, -size.height * 1.2),
    };
    _pending = kind;
    _burst = kind == SwipeKind.superLike && !reduce;
    _fly = Tween<Offset>(
      begin: _drag,
      end: end,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.duration = Duration(milliseconds: reduce ? 150 : 300);
    _controller.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _drag = Offset.zero;
        _fly = null;
        _pending = null;
        _burst = false;
        _controller.reset();
      });
      widget.onSwipe(kind);
    });
    setState(() {});
  }

  void _springBack() {
    _fly = Tween<Offset>(
      begin: _drag,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.duration = const Duration(milliseconds: 200);
    _controller.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _drag = Offset.zero;
        _fly = null;
        _controller.reset();
      });
    });
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _pending != null) return;
    setState(() => _drag += details.delta);
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.enabled || _pending != null) return;
    final vx = details.velocity.pixelsPerSecond.dx;
    final vy = details.velocity.pixelsPerSecond.dy;
    final fling = vx.abs() >= _flingVelocity || vy.abs() >= _flingVelocity;
    if (_drag.dy < -_commitDistance && _drag.dy.abs() > _drag.dx.abs()) {
      _commit(SwipeKind.superLike);
    } else if (_drag.dx > _commitDistance) {
      _commit(SwipeKind.like);
    } else if (_drag.dx < -_commitDistance) {
      _commit(SwipeKind.pass);
    } else if (fling && _drag.distance > 12) {
      if (vy < 0 && vy.abs() > vx.abs()) {
        _commit(SwipeKind.superLike);
      } else if (vx > 0) {
        _commit(SwipeKind.like);
      } else {
        _commit(SwipeKind.pass);
      }
    } else {
      _springBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    if (cards.isEmpty) return const SizedBox.shrink();
    final top = cards.first;
    final second = cards.length > 1 ? cards[1] : null;
    final offset = _fly?.value ?? _drag;
    final sideways = (offset.dx.abs() / _commitDistance).clamp(0.0, 1.0);
    final upward = (offset.dy < 0 ? -offset.dy / _commitDistance : 0.0).clamp(
      0.0,
      1.0,
    );
    final stampKind = offset.dy < -20 && offset.dy.abs() > offset.dx.abs()
        ? SwipeKind.superLike
        : offset.dx >= 0
        ? SwipeKind.like
        : SwipeKind.pass;
    final stampOpacity = stampKind == SwipeKind.superLike ? upward : sideways;
    final lift = second == null ? 0.0 : 0.94 + 0.06 * sideways;
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (second != null)
                  _Card(key: ValueKey(second.id), card: second, scale: lift),
                _Card(
                  key: ValueKey(top.id),
                  card: top,
                  offset: offset,
                  rotation: offset.dx * _tiltPerPixel * math.pi / 180,
                  stamp: stampOpacity > 0.02
                      ? SwipeStamp(kind: stampKind, opacity: stampOpacity)
                      : null,
                  burst: _burst,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ActionBar(
          enabled: widget.enabled && _pending == null,
          onAction: _commit,
          onComment: widget.onComment,
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.card,
    this.offset = Offset.zero,
    this.rotation = 0,
    this.scale = 1,
    this.stamp,
    this.burst = false,
    super.key,
  });

  final DeckCard card;
  final Offset offset;
  final double rotation;
  final double scale;
  final Widget? stamp;
  final bool burst;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: rotation,
        child: Transform.scale(
          scale: scale,
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.96, end: 1),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  builder: (context, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: ProfileCard(card: card),
                ),
                if (stamp case final stamp?) Center(child: stamp),
                if (burst)
                  Center(
                    child: IgnorePointer(
                      child: Icon(
                        Icons.star_rounded,
                        size: 120,
                        color: c.accent.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
