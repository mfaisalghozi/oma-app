import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/oma_button.dart';
import '../../usage/application/usage_providers.dart';
import '../application/describe_controller.dart';
import '../application/describe_results_provider.dart';
import '../domain/entities/describe_criteria.dart';
import 'widgets/criteria_chips.dart';
import 'widgets/result_row.dart';

/// M14: Analyzing while the search runs, then Results or Error. One route,
/// because the board shows one screen that changes.
class DescribeResultsScreen extends ConsumerWidget {
  const DescribeResultsScreen({required this.searchId, super.key});

  final String searchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(describeControllerProvider);
    final c = context.oma;
    final query = state.search?.criteria?.originalQuery ?? state.draft;

    if (state.stage == DescribeStage.failed) {
      return _ErrorView(
        timedOut: state.timedOut,
        errorCode: state.errorCode,
        onRetry: () async {
          await ref.read(describeControllerProvider.notifier).retry();
          if (!context.mounted) return;
          final active = ref.read(describeControllerProvider).search?.id;
          if (active != null) context.go('/discover/results/$active');
        },
        onSwipe: () => context.go('/discover'),
      );
    }

    if (state.stage != DescribeStage.done) {
      return _AnalyzingView(query: query, criteria: state.criteria);
    }

    final results = ref.watch(describeResultsProvider(searchId));
    return results.when(
      loading: () => _AnalyzingView(query: query, criteria: state.criteria),
      error: (error, _) => _ErrorView(
        timedOut: false,
        errorCode: null,
        onRetry: () => ref.invalidate(describeResultsProvider(searchId)),
        onSwipe: () => context.go('/discover'),
      ),
      data: (data) {
        final left = ref.watch(dailyUsageProvider).value?.searches.available;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.go('/discover'),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Describe',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                  const Spacer(),
                  if (left != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: c.mint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$left left',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: c.primaryStrong,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '\u201c$query\u201d',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/discover?mode=describe'),
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CriteriaChips(criteria: data.criteria),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      data.isEmpty
                          ? 'No matches yet'
                          : 'Top ${data.rows.length} closest matches',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                  ),
                  Text(
                    'Sorted by fit',
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: data.isEmpty
                  ? _EmptyView(
                      onEdit: () => context.go('/discover?mode=describe'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      itemCount: data.rows.length,
                      itemBuilder: (context, index) =>
                          ResultRow(row: data.rows[index]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AnalyzingView extends StatelessWidget {
  const _AnalyzingView({required this.query, this.criteria});

  final String query;
  final DescribeCriteria? criteria;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u201c$query\u201d',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
          const SizedBox(height: 20),
          if (criteria == null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 88 + i * 12.0,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            )
          else
            CriteriaChips(criteria: criteria!, compact: true),
          const SizedBox(height: 20),
          Text(
            'OMA is reading profiles…',
            style: TextStyle(fontSize: 14, color: c.textMuted),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: c.card,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(height: 14, color: c.card),
                        const SizedBox(height: 8),
                        Container(width: 140, height: 12, color: c.card),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: c.textMuted),
          const SizedBox(height: 16),
          Text(
            'No one matches all of that yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: c.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try fewer must-haves. This search was counted.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.textMuted),
          ),
          const SizedBox(height: 20),
          OmaButton(label: 'Edit', onPressed: onEdit, expand: false),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.timedOut,
    required this.errorCode,
    required this.onRetry,
    required this.onSwipe,
  });

  final bool timedOut;
  final String? errorCode;
  final VoidCallback onRetry;
  final VoidCallback onSwipe;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: c.error),
          const SizedBox(height: 16),
          Text(
            timedOut
                ? 'This is taking longer than usual'
                : "Describe couldn't finish",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            timedOut
                ? 'It may still finish and count. Try again in a moment.'
                : "This search wasn't counted.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: c.textMuted),
          ),
          const SizedBox(height: 24),
          OmaButton(label: 'Try again', onPressed: timedOut ? null : onRetry),
          const SizedBox(height: 10),
          OmaButton(
            label: 'Swipe instead',
            variant: OmaButtonVariant.secondary,
            onPressed: onSwipe,
          ),
        ],
      ),
    );
  }
}
