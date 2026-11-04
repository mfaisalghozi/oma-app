import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/oma_button.dart';
import '../../../core/widgets/oma_scaffold.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/domain/entities/account_state.dart';

class RestrictedScreen extends ConsumerWidget {
  const RestrictedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).value;
    final account = session is SignedIn ? session.account : null;
    final frozen = account?.status == AccountStatus.frozen;
    return OmaScaffold(
      showBack: false,
      title: frozen ? 'Your account is frozen' : 'Your account is suspended',
      subtitle: frozen
          ? 'Unfreeze it to show up in Discover again.'
          : 'You can still open Settings, contact support or sign out.',
      body: const SizedBox.shrink(),
      bottom: OmaButton.secondary(
        label: 'Sign out',
        onPressed: () => ref.read(sessionControllerProvider.notifier).signOut(),
      ),
    );
  }
}
