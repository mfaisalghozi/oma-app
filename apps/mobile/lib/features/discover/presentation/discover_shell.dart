import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../usage/application/usage_providers.dart';
import '../../usage/presentation/usage_pill.dart';
import '../../describe/presentation/describe_screen.dart';
import 'discover_mode.dart';
import 'swipe_screen.dart';
import 'widgets/discover_header.dart';
import 'widgets/mode_switch.dart';

class DiscoverShell extends ConsumerWidget {
  const DiscoverShell({
    required this.mode,
    required this.describeEnabled,
    super.key,
  });

  final DiscoverMode mode;
  final bool describeEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(dailyUsageProvider);
    final kind = mode == DiscoverMode.swipe
        ? UsagePillKind.likes
        : UsagePillKind.searches;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: DiscoverHeader(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: ModeSwitch(
              mode: mode,
              showDescribe: describeEnabled,
              onChanged: (next) =>
                  context.go('${Routes.discover}?mode=${next.query}'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: usage.when(
                data: (value) => UsagePill(usage: value, kind: kind),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          Expanded(
            child: mode == DiscoverMode.swipe
                ? SwipeScreen(describeEnabled: describeEnabled)
                : const DescribeScreen(),
          ),
        ],
      ),
    );
  }
}
