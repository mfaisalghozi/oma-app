import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/oma_banner.dart';
import '../../../core/widgets/oma_button.dart';
import '../../../core/widgets/oma_scaffold.dart';
import '../application/auth_providers.dart';
import '../application/email_auth_controller.dart';

/// M04c Check your email. The confirmation link opens `/auth/callback` on
/// this phone; supabase_flutter turns it into a session and the gates move
/// on to M05.
class CheckInboxScreen extends ConsumerStatefulWidget {
  const CheckInboxScreen({super.key});

  @override
  ConsumerState<CheckInboxScreen> createState() => _CheckInboxScreenState();
}

class _CheckInboxScreenState extends ConsumerState<CheckInboxScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _useDifferentEmail() {
    ref.read(pendingEmailConfirmationProvider.notifier).set(null);
    context.go(Routes.signUpEmail);
  }

  Future<void> _openMailApp() async {
    // iOS opens Mail's inbox; Android has no URL for "inbox", so this opens
    // the mail app chooser through mailto.
    final uri = Uri.parse(Platform.isIOS ? 'message://' : 'mailto:');
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app found on this phone.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final email = ref.watch(pendingEmailConfirmationProvider) ?? 'your email';
    final resend = ref.watch(resendControllerProvider);
    final now = ref.watch(clockProvider)();
    final wait = resend.availableAt.difference(now);
    final waiting = wait > Duration.zero;
    final secs = wait.inSeconds + (wait.inMilliseconds % 1000 > 0 ? 1 : 0);

    return OmaScaffold(
      onBack: _useDifferentEmail,
      body: Column(
        children: [
          const SizedBox(height: 48),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
            child: Icon(
              Icons.mark_email_unread_outlined,
              size: 44,
              color: c.primaryStrong,
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            header: true,
            child: Text(
              'Check your email',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontSize: 26),
            ),
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 15, height: 1.45, color: c.textMuted),
              children: [
                const TextSpan(text: 'We sent a confirmation link to '),
                TextSpan(
                  text: email,
                  style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
                ),
                const TextSpan(
                  text:
                      ". Tap it on this phone and you'll come straight back to "
                      'OMA.',
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          if (resend.error != null) ...[
            const SizedBox(height: 16),
            OmaBanner(
              message: resend.error is EmailAuthRateLimited
                  ? 'Too many requests. Wait a minute, then try again.'
                  : "We couldn't resend the link. Please try again.",
            ),
          ] else if (resend.sent) ...[
            const SizedBox(height: 16),
            const OmaBanner(
              tone: OmaBannerTone.info,
              message: 'New link sent. Check your inbox.',
            ),
          ],
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OmaButton(
            label: 'Open email app',
            icon: const Icon(Icons.mail_outline_rounded, size: 20),
            onPressed: _openMailApp,
          ),
          const SizedBox(height: 12),
          OmaButton.secondary(
            label: waiting
                ? 'Resend link in 0:${secs.toString().padLeft(2, '0')}'
                : 'Resend link',
            loading: resend.busy,
            onPressed: waiting
                ? null
                : () => ref
                      .read(resendControllerProvider.notifier)
                      .resend(ref.read(pendingEmailConfirmationProvider) ?? ''),
          ),
          TextButton(
            onPressed: _useDifferentEmail,
            style: TextButton.styleFrom(
              foregroundColor: c.primary,
              minimumSize: const Size(44, 44),
            ),
            child: const Text(
              'Use a different email',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            "Can't find it? Check Spam or Promotions.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}
