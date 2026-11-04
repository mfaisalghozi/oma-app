import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/legal_links.dart';
import '../../../core/widgets/oma_button.dart';
import '../../auth/application/session_controller.dart';
import '../application/onboarding_submit_controller.dart';
import '../domain/entities/onboarding_step.dart';

/// M11b "Setting up your profile" and M11c "We couldn't finish your
/// profile". Submits on open; Try again repeats the same call.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(onboardingSubmitProvider);
      if (s is! SubmitRunning) {
        unawaited(ref.read(onboardingSubmitProvider.notifier).submit());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(onboardingSubmitProvider, (_, next) {
      if (next is SubmitNeedsFix) {
        context.go(Routes.onboardingStep(next.step.path));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please check your answers on this step.'),
          ),
        );
      }
    });
    final state = ref.watch(onboardingSubmitProvider);
    final failed = state is SubmitFailed;
    final c = context.oma;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: failed ? c.errorSurface : c.mint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    failed ? Icons.cloud_off_outlined : Icons.waves,
                    size: 44,
                    color: failed ? c.error : c.primary,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  failed
                      ? "We couldn't finish your profile"
                      : 'Setting up your profile',
                  textAlign: TextAlign.center,
                  style: t.headlineSmall,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                failed
                    ? 'The connection dropped while saving. Everything you '
                          "entered is kept on this phone, so you won't need "
                          'to fill anything in again.'
                    : 'This takes a few seconds. Keep the app open.',
                textAlign: TextAlign.center,
                style: t.bodyLarge?.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: 32),
              for (final phase in SetupPhase.values)
                _PhaseRow(phase: phase, status: state.statusOf(phase)),
              const Spacer(),
              if (failed) ...[
                OmaButton(
                  label: 'Try again',
                  onPressed: ref.read(onboardingSubmitProvider.notifier).submit,
                ),
                const SizedBox(height: 8),
                OmaButton.secondary(
                  label: 'Review my answers',
                  onPressed: () => context.go(
                    Routes.onboardingStep(OnboardingStep.basics.path),
                  ),
                ),
                const SizedBox(height: 4),
                OmaButton.text(
                  label: 'Still stuck? Contact support',
                  onPressed: () => openExternalPage(
                    Uri.parse('${ref.read(appConfigProvider).webBaseUrl}/help'),
                  ),
                ),
              ],
              if (state is SubmitDone)
                OmaButton(
                  label: 'Continue',
                  onPressed: () =>
                      ref.read(sessionControllerProvider.notifier).refresh(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseRow extends StatelessWidget {
  const _PhaseRow({required this.phase, required this.status});

  final SetupPhase phase;
  final PhaseStatus status;

  static const _labels = {
    SetupPhase.saving: 'Saving your answers',
    SetupPhase.photos: 'Checking your photos',
    SetupPhase.finding: 'Finding people near you',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final (Widget icon, String spoken) = switch (status) {
      PhaseStatus.done => (
        Icon(Icons.check_circle, color: c.primary, size: 24),
        'Done',
      ),
      PhaseStatus.running => (
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        'In progress',
      ),
      PhaseStatus.failed => (
        Icon(Icons.error, color: c.error, size: 24),
        'Failed',
      ),
      PhaseStatus.waiting => (
        Icon(Icons.radio_button_unchecked, color: c.border, size: 24),
        'Waiting',
      ),
    };
    return Semantics(
      label: '${_labels[phase]}, $spoken',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox.square(dimension: 24, child: Center(child: icon)),
            const SizedBox(width: 14),
            Text(
              _labels[phase]!,
              style: TextStyle(
                fontSize: 16,
                fontWeight: status == PhaseStatus.running
                    ? FontWeight.w700
                    : FontWeight.w600,
                color: status == PhaseStatus.waiting ? c.textMuted : c.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
