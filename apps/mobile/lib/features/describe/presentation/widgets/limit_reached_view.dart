import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../../../core/widgets/coming_soon_sheet.dart';
import '../../../../core/widgets/oma_button.dart';
import '../../../usage/domain/entities/daily_usage.dart';
import '../../application/describe_controller.dart';

/// M13 with no searches left. Red counter, PRO placeholder, and See my last
/// results only if this session already had a successful search.
class LimitReachedView extends ConsumerWidget {
  const LimitReachedView({
    required this.usage,
    required this.lastResultsId,
    super.key,
  });

  final DailyUsage usage;
  final String? lastResultsId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.oma;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
              child: Icon(
                Icons.search_off_rounded,
                size: 40,
                color: c.primaryStrong,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "That's your 3 searches for today",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'More searches tomorrow, or get 20 a day with PRO.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.45, color: c.textMuted),
          ),
          const SizedBox(height: 24),
          OmaButton(
            label: 'Get 20 searches a day with PRO',
            onPressed: () => showComingSoonSheet(
              context,
              title: 'PRO is coming soon',
              body: 'PRO gives you 20 searches and more likes every day.',
            ),
          ),
          if (lastResultsId != null) ...[
            const SizedBox(height: 10),
            OmaButton(
              label: 'See my last results',
              variant: OmaButtonVariant.secondary,
              onPressed: () => ref
                  .read(describeControllerProvider.notifier)
                  .openLastResults(lastResultsId!),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}
