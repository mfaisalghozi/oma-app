import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/oma_error_view.dart';
import '../../application/onboarding_draft_controller.dart';
import '../../domain/entities/onboarding_draft.dart';

/// Shows [builder] once the draft is loaded.
class DraftBuilder extends ConsumerWidget {
  const DraftBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, OnboardingDraft draft) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(onboardingDraftProvider);
    return switch (draft) {
      AsyncData(value: final d?) => builder(context, d),
      AsyncError(:final error) => Scaffold(
        body: SafeArea(
          child: Center(
            child: OmaErrorView(
              error: error,
              onRetry: () => ref.invalidate(onboardingDraftProvider),
            ),
          ),
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
