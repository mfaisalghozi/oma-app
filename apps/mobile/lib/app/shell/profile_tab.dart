import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/session_controller.dart';
import '../../core/widgets/oma_button.dart';
import '../../core/widgets/oma_scaffold.dart';

/// The Profile tab keeps the only account action built so far: sign out.
class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OmaScaffold(
      showBack: false,
      title: 'Profile',
      body: OmaButton.secondary(
        label: 'Sign out',
        onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
      ),
    );
  }
}
