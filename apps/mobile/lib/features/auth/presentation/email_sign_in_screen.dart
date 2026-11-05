import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/legal_links.dart';
import '../../../core/widgets/oma_banner.dart';
import '../../../core/widgets/oma_button.dart';
import '../../../core/widgets/oma_field.dart';
import '../../../core/widgets/oma_scaffold.dart';
import '../application/email_auth_controller.dart';
import '../domain/entities/password_rules.dart';

class EmailSignInScreen extends ConsumerStatefulWidget {
  const EmailSignInScreen({this.createAccount = false, super.key});

  final bool createAccount;

  @override
  ConsumerState<EmailSignInScreen> createState() => _EmailSignInScreenState();
}

/// Survives the tab swap so the email is not lost.
final _typedEmail = NotifierProvider<_TypedEmail, String>(_TypedEmail.new);

class _TypedEmail extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

class _EmailSignInScreenState extends ConsumerState<EmailSignInScreen> {
  late final _email = TextEditingController(text: ref.read(_typedEmail));
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _create => widget.createAccount;

  void _switchTab(bool create) {
    if (create == _create) return;
    ref.read(_typedEmail.notifier).set(_email.text);
    ref.read(emailAuthControllerProvider.notifier).clear();
    context.go(create ? Routes.signUpEmail : Routes.signInEmail);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final controller = ref.read(emailAuthControllerProvider.notifier);
    final outcome = _create
        ? await controller.signUp(_email.text, _password.text)
        : await controller.signIn(_email.text, _password.text);
    if (!mounted) return;
    if (outcome == EmailAuthOutcome.checkInbox) {
      context.go(Routes.checkInbox);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final state = ref.watch(emailAuthControllerProvider);
    ref.listen(emailAuthControllerProvider, (_, next) {
      if (next.notice != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.notice!)));
      }
    });
    final rules = PasswordRules(_password.text);
    final error = state.error;
    final locked = error is LockedOut;
    final canSubmit = _create
        ? rules.valid && _email.text.isNotEmpty
        : _email.text.isNotEmpty && _password.text.isNotEmpty && !locked;

    return OmaScaffold(
      onBack: () =>
          context.canPop() ? context.pop() : context.go(Routes.signIn),
      title: _create ? 'Create your account' : 'Sign in with email',
      body: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Tabs(createAccount: _create, onChanged: _switchTab),
            const SizedBox(height: 24),
            if (error != null &&
                error is! WrongPassword &&
                error is! InvalidEmail) ...[
              OmaBanner(message: _bannerText(error)),
              const SizedBox(height: 16),
            ],
            OmaField(
              label: 'Email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              errorText: error is InvalidEmail ? 'Enter a full email' : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            OmaField(
              label: 'Password',
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              autofillHints: [
                _create ? AutofillHints.newPassword : AutofillHints.password,
              ],
              errorText: error is WrongPassword
                  ? 'Wrong email or password. ${_tries(error.triesLeft)} left '
                        'before a 15-minute pause.'
                  : null,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => canSubmit ? _submit() : null,
              suffix: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: c.textMuted,
                ),
              ),
            ),
            if (_create) ...[
              const SizedBox(height: 12),
              _Rule(label: 'At least 8 characters', met: rules.longEnough),
              const SizedBox(height: 6),
              _Rule(
                label: 'Has a letter and a number',
                met: rules.hasLetterAndNumber,
              ),
              const SizedBox(height: 16),
              Text(
                "We'll send a link to this email to confirm it's yours.",
                style: TextStyle(fontSize: 14, color: c.textMuted),
              ),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: state.busy
                      ? null
                      : () => ref
                            .read(emailAuthControllerProvider.notifier)
                            .forgotPassword(_email.text),
                  style: TextButton.styleFrom(
                    foregroundColor: c.primary,
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OmaButton(
            label: _create ? 'Create account' : 'Sign in',
            loading: state.busy,
            onPressed: canSubmit ? _submit : null,
          ),
          if (_create) ...[
            const SizedBox(height: 12),
            const LegalLinksText(
              prefix: '18+ only. By creating an account you agree to our ',
            ),
          ],
        ],
      ),
    );
  }

  static String _tries(int n) => n == 1 ? '1 try' : '$n tries';

  static String _bannerText(EmailAuthError e) => switch (e) {
    LockedOut(:final until) =>
      'Too many wrong tries. Sign-in is paused until '
          '${TimeOfDay.fromDateTime(until.toLocal()).format24()}. '
          'You can reset your password meanwhile.',
    EmailAuthOffline() =>
      "You're offline. Check your connection and try again.",
    EmailAuthRateLimited() =>
      'Too many requests. Wait a minute, then try again.',
    _ => "That didn't work. Please try again.",
  };
}

extension on TimeOfDay {
  String format24() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.createAccount, required this.onChanged});

  final bool createAccount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    Widget tab(String label, bool create) {
      final selected = create == createAccount;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(create);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.background : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? c.text : c.textMuted,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [tab('Sign in', false), tab('Create account', true)],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Semantics(
      label: '$label, ${met ? 'met' : 'not met yet'}',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: met ? c.primary : c.textMuted,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: met ? c.primaryStrong : c.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
