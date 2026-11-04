import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/legal_links.dart';
import '../../../core/widgets/oma_banner.dart';
import '../../../core/widgets/oma_button.dart';
import '../../../core/widgets/oma_error_view.dart';
import '../../../core/widgets/oma_scaffold.dart';
import '../application/consent_controller.dart';
import '../domain/entities/consent_document.dart';

/// M05 "Your data, your call" (UU PDP explicit consent).
///
/// Rows come from `GET /v1/consents/documents`, so the backend decides how
/// many ticks there are. Known types get the v0.1 explainer line; unknown
/// ones show just their title.
class ConsentScreen extends ConsumerWidget {
  const ConsentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(consentControllerProvider);
    final notifier = ref.read(consentControllerProvider.notifier);

    return switch (async) {
      AsyncData(:final value) => _ConsentForm(
        state: value,
        onToggle: notifier.toggle,
        onSubmit: notifier.submit,
      ),
      AsyncError(:final error) => Scaffold(
        body: SafeArea(
          child: Center(
            child: OmaErrorView(
              error: error,
              title: "We couldn't load the agreements",
              onRetry: () => ref.invalidate(consentControllerProvider),
            ),
          ),
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _ConsentForm extends StatelessWidget {
  const _ConsentForm({
    required this.state,
    required this.onToggle,
    required this.onSubmit,
  });

  final ConsentState state;
  final ValueChanged<String> onToggle;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final theme = Theme.of(context);
    final error = state.error;

    return OmaScaffold(
      showBack: false,
      title: 'Your data, your call',
      subtitle:
          'OMA is a dating app, so some of what you share is sensitive under '
          'UU PDP. We need your clear OK for each item below.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final doc in state.documents) ...[
            _ConsentTile(
              document: doc,
              ticked: state.ticked.contains(doc.type),
              enabled: !state.saving,
              onToggle: () => onToggle(doc.type),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          Text(
            'You can withdraw consent any time in Settings. Withdrawing '
            'deletes your account.',
            style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
          ),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            OmaBanner(
              message: _errorText(error),
              actionLabel: 'Try again',
              onAction: onSubmit,
            ),
            const SizedBox(height: 12),
          ],
          OmaButton(
            label: 'Agree and continue',
            loading: state.saving,
            onPressed: state.canContinue ? onSubmit : null,
          ),
          if (!state.canContinue && !state.saving) ...[
            const SizedBox(height: 8),
            Text(
              'Check all to continue.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  static String _errorText(Failure f) => switch (f) {
    NetworkFailure() =>
      "You're offline. Your ticks are kept, try again when you're back.",
    _ => "We couldn't save that. Your ticks are kept, please try again.",
  };
}

class _ConsentTile extends ConsumerWidget {
  const _ConsentTile({
    required this.document,
    required this.ticked,
    required this.enabled,
    required this.onToggle,
  });

  final ConsentDocument document;
  final bool ticked;
  final bool enabled;
  final VoidCallback onToggle;

  /// v0.1 explainer lines for the types in BE doc §8.3.
  static const _explainers = {
    'sensitive_data':
        'Religion, relationship intent, height and weight are used only to '
        'show and rank matches. Never in ads or analytics.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.oma;
    final theme = Theme.of(context);
    final explainer = _explainers[document.type];
    final url = _resolve(ref.watch(appConfigProvider), document.documentUrl);

    return Material(
      color: ticked ? c.mint : c.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onToggle : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: ticked,
                onChanged: enabled ? (_) => onToggle() : null,
                semanticLabel: document.title,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(document.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        document.required ? 'Required' : 'Optional',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: document.required ? c.accent : c.textMuted,
                        ),
                      ),
                      if (explainer != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          explainer,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: c.textMuted,
                          ),
                        ),
                      ],
                      if (url != null)
                        TextButton(
                          onPressed: () => openExternalPage(url),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(44, 36),
                            alignment: Alignment.centerLeft,
                            foregroundColor: c.primary,
                          ),
                          child: Text(
                            'Read the ${document.title}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `document_url` may be absolute or relative to the public web.
  static Uri? _resolve(AppConfig config, String raw) {
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    return uri.hasScheme ? uri : Uri.parse(config.webBaseUrl).resolveUri(uri);
  }
}
