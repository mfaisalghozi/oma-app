import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/oma_banner.dart';
import '../../../core/widgets/oma_button.dart';
import '../../../core/widgets/oma_scaffold.dart';
import '../application/auth_providers.dart';
import '../application/sign_in_controller.dart';

/// M02 sign-in hub: one screen for new and returning users.
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.oma;
    final state = ref.watch(signInControllerProvider);
    final controller = ref.read(signInControllerProvider.notifier);
    final config = ref.watch(appConfigProvider);
    final appleAvailable = ref
        .watch(socialAuthRepositoryProvider)
        .appleAvailable;
    final busy = state.busy != null;

    return OmaScaffold(
      title: 'Sign in or create an account',
      subtitle: 'Pick one. You can link the others later in Settings.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          if (state.error != null) ...[
            OmaBanner(
              message: _errorMessage(state.error!),
              actionLabel: 'Try again',
              onAction: controller.retry,
            ),
            const SizedBox(height: 16),
          ],
          OmaButton.secondary(
            label: 'Continue with Google',
            icon: const Icon(Icons.public_rounded, size: 20),
            loading: state.busy == SocialProvider.google,
            onPressed: busy
                ? null
                : () => controller.signIn(SocialProvider.google),
          ),
          if (appleAvailable) ...[
            const SizedBox(height: 12),
            OmaButton.secondary(
              label: 'Continue with Apple',
              icon: const Icon(Icons.apple_rounded, size: 22),
              loading: state.busy == SocialProvider.apple,
              onPressed: busy
                  ? null
                  : () => controller.signIn(SocialProvider.apple),
            ),
          ],
          // Phone OTP (M03, E2-05) is out of this scope and hidden behind the
          // AUTH_PHONE_ENABLED build flag until an SMS provider is chosen.
          if (config.authPhoneEnabled) ...[
            const SizedBox(height: 12),
            OmaButton.secondary(
              label: 'Continue with phone number',
              icon: const Icon(Icons.smartphone_rounded, size: 20),
              onPressed: busy
                  ? null
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Phone sign-in is coming soon.'),
                      ),
                    ),
            ),
          ],
          const SizedBox(height: 12),
          OmaButton.secondary(
            label: 'Continue with email',
            icon: const Icon(Icons.mail_outline_rounded, size: 20),
            onPressed: busy ? null : () => context.push(Routes.signInEmail),
          ),
        ],
      ),
      bottom: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 20, color: c.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'We never post anything to your accounts.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _errorMessage(AuthFailure e) => switch (e.kind) {
    AuthFailureKind.network =>
      "You're offline. Check your connection and try again.",
    AuthFailureKind.rateLimited =>
      'Too many tries. Wait a minute, then try again.',
    _ => "We couldn't sign you in. Please try again.",
  };
}
