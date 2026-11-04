import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/oma_error_view.dart';
import '../application/session_controller.dart';

/// M00. Shown while the session restores; the gates move on as soon as the
/// session resolves. ONB-FE-02 adds the intro animation.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    return Scaffold(
      backgroundColor: context.oma.splash,
      body: Center(
        child: session.hasError && !session.isLoading
            ? OmaErrorView(
                error: session.error,
                onRetry: () =>
                    ref.read(sessionControllerProvider.notifier).retry(),
              )
            : const OmaAppIcon(size: 160),
      ),
    );
  }
}
