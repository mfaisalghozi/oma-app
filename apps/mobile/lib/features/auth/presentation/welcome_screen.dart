import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/legal_links.dart';
import '../../../core/widgets/oma_button.dart';

/// M01 Welcome, for signed-out users. Both CTAs open the M02 sign-in hub,
/// which serves new and returning users.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                decoration: BoxDecoration(
                  color: c.mint,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Image.asset(
                                BrandAssets.wordmark,
                                height: 32,
                                semanticLabel: 'OMA',
                              ),
                              const Spacer(),
                              Text(
                                'Ocean Match',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.primaryStrong,
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: OmaAppIcon(size: 148)),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  "There's plenty of fish in the ocean. "
                                  'Find yours here.',
                                  style: text.displaySmall,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Tell OMA in your own words, and it finds the '
                                'closest real matches near you.',
                                style: text.bodyLarge,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                children: [
                  OmaButton(
                    label: 'Get started',
                    onPressed: () => context.push(Routes.signIn),
                  ),
                  const SizedBox(height: 12),
                  OmaButton.secondary(
                    label: 'I already have an account',
                    onPressed: () => context.push(Routes.signIn),
                  ),
                  const SizedBox(height: 12),
                  const LegalLinksText(
                    prefix: '18+ only. By continuing you agree to our ',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
