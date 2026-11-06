import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/oma_button.dart';
import '../../../core/widgets/placeholder_screen.dart';
import '../../auth/application/session_controller.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlaceholderScreen(
      screenId: 'M12',
      title: 'Discover',
      ticket: 'the Discover feature',
      actions: [
        OmaButton.secondary(
          label: 'Sign out',
          onPressed: () =>
              ref.read(sessionControllerProvider.notifier).signOut(),
        ),
      ],
    );
  }
}
