import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../../../core/widgets/oma_button.dart';
import '../../../device/application/device_registrar.dart';
import '../../application/onboarding_draft_controller.dart';
import '../../application/onboarding_resume.dart';
import '../../domain/entities/onboarding_step.dart';
import '../widgets/draft_builder.dart';
import '../widgets/step_frame.dart';

/// M11 Don't miss a match: our own pre-prompt; the OS dialog only shows
/// after Turn on notifications.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      DraftBuilder(builder: (_, _) => const _NotificationsBody());
}

class _NotificationsBody extends ConsumerStatefulWidget {
  const _NotificationsBody();

  @override
  ConsumerState<_NotificationsBody> createState() => _NotificationsBodyState();
}

class _NotificationsBodyState extends ConsumerState<_NotificationsBody> {
  bool _busy = false;

  Future<void> _turnOn() async {
    setState(() => _busy = true);
    var allowed = false;
    try {
      allowed = await ref.read(pushServiceProvider).requestPermission();
    } on Object {
      // A broken permission call never blocks onboarding.
    }
    if (allowed) {
      // In the background: registration failure must not block onboarding.
      unawaited(ref.read(deviceRegistrarProvider).register());
    }
    await _done();
  }

  Future<void> _done() async {
    await ref
        .read(onboardingDraftProvider.notifier)
        .edit((d) => d.copyWith(notificationsDecided: true));
    if (mounted) context.go(nextStepPath(OnboardingStep.notifications));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return StepFrame(
      step: OnboardingStep.notifications,
      title: "Don't miss a match",
      subtitle:
          "Turn on notifications and we'll tell you when you match or get a "
          'message. Nothing else, no promos.',
      canContinue: !_busy,
      nextLabel: 'Turn on notifications',
      onNext: _turnOn,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _Example(
            icon: Icons.favorite,
            title: 'New match',
            body: 'When you and someone like each other.',
            color: c.accent,
          ),
          const SizedBox(height: 12),
          _Example(
            icon: Icons.chat_bubble,
            title: 'New message',
            body: 'When a match writes to you.',
            color: c.primary,
          ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OmaButton.text(
          label: 'Maybe later',
          onPressed: _busy ? null : _done,
        ),
      ),
    );
  }
}

/// What the user will be notified about (and nothing else).
class _Example extends StatelessWidget {
  const _Example({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color,
            child: Icon(icon, color: c.background, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: t.bodyMedium?.copyWith(color: c.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
