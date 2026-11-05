import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/oma_error_view.dart';
import '../application/session_controller.dart';
import 'widgets/splash_intro.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final failed = session.hasError && !session.isLoading;
    return Scaffold(
      backgroundColor: context.oma.splash,
      body: SafeArea(
        child: failed
            ? Center(
                child: OmaErrorView(
                  error: session.error,
                  onRetry: () =>
                      ref.read(sessionControllerProvider.notifier).retry(),
                ),
              )
            : const SizedBox.expand(child: SplashIntro()),
      ),
    );
  }
}
