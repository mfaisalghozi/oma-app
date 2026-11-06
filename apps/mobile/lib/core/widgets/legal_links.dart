import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../theme/oma_colors.dart';

Future<void> openExternalPage(Uri url) async {
  // Backend-supplied legal/support links must never open a local or app scheme.
  if (!url.isScheme('http') && !url.isScheme('https')) return;
  await launchUrl(url, mode: LaunchMode.inAppBrowserView);
}

class LegalLinksText extends ConsumerStatefulWidget {
  const LegalLinksText({required this.prefix, super.key});

  final String prefix;

  @override
  ConsumerState<LegalLinksText> createState() => _LegalLinksTextState();
}

class _LegalLinksTextState extends ConsumerState<LegalLinksText> {
  late final _terms = TapGestureRecognizer();
  late final _privacy = TapGestureRecognizer();

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final config = ref.watch(appConfigProvider);
    _terms.onTap = () => openExternalPage(config.termsUrl);
    _privacy.onTap = () => openExternalPage(config.privacyUrl);
    final link = TextStyle(
      color: c.primary,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: c.primary,
    );
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 12, height: 1.5, color: c.textMuted),
        children: [
          TextSpan(text: widget.prefix),
          TextSpan(text: 'Terms', style: link, recognizer: _terms),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
