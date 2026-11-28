import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/coming_soon_sheet.dart';
import '../../../core/widgets/oma_banner.dart';
import '../../usage/application/usage_providers.dart';
import '../../usage/domain/entities/daily_usage.dart';
import '../application/deck_controller.dart';
import '../domain/deck_state.dart';
import '../domain/entities/swipe_kind.dart';
import '../domain/usecases/submit_swipe.dart';
import 'widgets/deck_state_card.dart';
import 'widgets/swipe_deck.dart';

/// The M12 deck area. Header and mode switch stay in [DiscoverShell].
class SwipeScreen extends ConsumerWidget {
  const SwipeScreen({required this.describeEnabled, super.key});

  final bool describeEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deck = ref.watch(deckControllerProvider);
    final usage = ref.watch(dailyUsageProvider).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: deck.when(
        loading: () => const _DeckSkeleton(),
        error: (error, _) => _stateCard(
          context,
          ref,
          const DeckState(status: DeckStatus.error),
          usage,
        ),
        data: (state) =>
            state.status == DeckStatus.ready && state.cards.isNotEmpty
            ? _deck(context, ref, state)
            : _stateCard(context, ref, state, usage),
      ),
    );
  }

  Widget _deck(BuildContext context, WidgetRef ref, DeckState state) {
    return Column(
      children: [
        if (state.queued) ...[
          const OmaBanner(
            message:
                "You're offline. Your decisions will be sent when you're back.",
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: SwipeDeck(
            cards: state.cards,
            onSwipe: (kind) => _swipe(context, ref, kind),
            onComment: () => _comingSoon(
              context,
              title: 'Comments are coming soon',
              body: 'For now, swipe or super like to show interest.',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _swipe(
    BuildContext context,
    WidgetRef ref,
    SwipeKind kind,
  ) async {
    final outcome = await ref.read(deckControllerProvider.notifier).swipe(kind);
    if (!context.mounted) return;
    if (outcome == SwipeOutcome.superLikeEmpty) {
      await _comingSoon(
        context,
        title: 'Super likes are coming soon',
        body: 'Your card came back. Nothing was charged.',
      );
    }
  }

  Widget _stateCard(
    BuildContext context,
    WidgetRef ref,
    DeckState state,
    DailyUsage? usage,
  ) {
    void reload() => ref.read(deckControllerProvider.notifier).reload();
    switch (state.status) {
      case DeckStatus.outOfLikes:
        final limit = usage?.likes.limit;
        final reset = usage == null ? null : _clock(usage.resetsAt);
        return DeckStateCard(
          icon: Icons.favorite_border_rounded,
          title: limit == null
              ? "That's your likes for today"
              : "That's your $limit likes for today",
          body: reset == null
              ? 'More likes at midnight. You can still pass, look at profiles '
                    'and chat with your matches.'
              : 'More likes at $reset. You can still pass, look at profiles '
                    'and chat with your matches.',
          nudge: usage != null && !usage.profileComplete
              ? const _ProfileNudge()
              : null,
          primaryLabel: 'See PRO',
          onPrimary: () => _comingSoon(
            context,
            title: 'PRO is coming soon',
            body: 'PRO gives you more likes and searches every day.',
          ),
          // TODO(decide): where "Finish my profile" goes is still open in SA 16.
          secondaryLabel: 'Finish my profile',
          onSecondary: () => _comingSoon(
            context,
            title: 'Finish my profile',
            body: 'Profile editing arrives with the next sprint.',
          ),
        );
      case DeckStatus.outOfFish:
        return DeckStateCard(
          icon: Icons.explore_outlined,
          title: "You've seen everyone new nearby",
          body:
              'New people join every day, so check back tomorrow. '
              'Or describe who you want and let OMA look wider.',
          primaryLabel: describeEnabled ? 'Describe who I want' : 'Try again',
          onPrimary: describeEnabled
              ? () => _switchToDescribe(context)
              : reload,
          secondaryLabel: describeEnabled ? 'Try again' : null,
          onSecondary: describeEnabled ? reload : null,
        );
      case DeckStatus.offlineEmpty:
        return DeckStateCard(
          icon: Icons.wifi_off_rounded,
          title: "You're offline",
          body: 'Check your connection and try again.',
          primaryLabel: 'Try again',
          onPrimary: reload,
        );
      case DeckStatus.ready:
        return const _DeckSkeleton();
      case DeckStatus.error:
        return DeckStateCard(
          icon: Icons.cloud_off_rounded,
          title: "Something didn't load",
          body: 'Nothing was lost. Please try again.',
          primaryLabel: 'Try again',
          onPrimary: reload,
        );
    }
  }

  void _switchToDescribe(BuildContext context) {
    context.go('/discover?mode=describe');
  }

  static String _clock(DateTime when) {
    final local = when.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _comingSoon(
    BuildContext context, {
    required String title,
    required String body,
  }) => showComingSoonSheet(context, title: title, body: body);
}

class _ProfileNudge extends StatelessWidget {
  const _ProfileNudge();

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, color: c.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Complete your profile for 15 more likes every day.',
              style: TextStyle(fontSize: 13, height: 1.35, color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckSkeleton extends StatelessWidget {
  const _DeckSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(28),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.mint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _Bar(width: 160, colour: c.border),
                const SizedBox(height: 10),
                _Bar(width: 220, colour: c.border),
                const SizedBox(height: 10),
                _Bar(width: 120, colour: c.border),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const _SkeletonActions(),
      ],
    );
  }
}

class _SkeletonActions extends StatelessWidget {
  const _SkeletonActions();

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final size in const [56.0, 56.0, 56.0, 64.0])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: c.card, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.colour});

  final double width;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
