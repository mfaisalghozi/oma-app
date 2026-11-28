import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/oma_colors.dart';
import '../../../core/widgets/coming_soon_sheet.dart';
import '../../../core/widgets/oma_button.dart';
import '../../usage/application/usage_providers.dart';
import '../application/describe_controller.dart';
import 'widgets/limit_reached_view.dart';

/// M13. The board: a box, example prompts, a counter and one button.
class DescribeScreen extends ConsumerStatefulWidget {
  const DescribeScreen({super.key});

  static const minChars = 3;
  static const maxChars = 500;

  @override
  ConsumerState<DescribeScreen> createState() => _DescribeScreenState();
}

class _DescribeScreenState extends ConsumerState<DescribeScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    final usage = ref.watch(dailyUsageProvider).value;
    final state = ref.watch(describeControllerProvider);
    final exhausted = usage?.searches.isExhausted ?? false;

    if (exhausted) {
      return LimitReachedView(
        usage: usage!,
        lastResultsId: state.lastSuccessSearchId,
      );
    }

    final length = _controller.text.trim().length;
    final tooLong = length > DescribeScreen.maxChars;
    final canSubmit = length >= DescribeScreen.minChars && !tooLong;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            minLines: 4,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (value) {
              ref.read(describeControllerProvider.notifier).setDraft(value);
              setState(() {});
            },
            decoration: InputDecoration(
              labelText: 'Describe the person you want',
              hintText: 'Male, min 180cm, brown hair, suka hiking',
              errorText: tooLong ? 'Keep it under 500 characters' : null,
              helperText: 'Bahasa or English',
              suffixIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: OmaButton(
                  label: 'Find matches',
                  icon: const Icon(Icons.search_rounded, size: 18),
                  expand: false,
                  onPressed: canSubmit ? _submit : null,
                  onDisabledTap: canSubmit
                      ? null
                      : () {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Describe them in at least 3 characters.',
                                ),
                              ),
                            );
                        },
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Try one of these',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final prompt in _prompts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ExampleCard(
                      text: prompt,
                      onTap: () {
                        _controller.text = prompt;
                        ref
                            .read(describeControllerProvider.notifier)
                            .setDraft(prompt);
                        setState(() {});
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flare_rounded, size: 16, color: c.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'OMA searches what people wrote on their profiles. '
                        'It never reads photos.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: c.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    // DSB-FE-02 starts the search; this ticket only validates the box.
    showComingSoonSheet(
      context,
      title: 'Search is not wired yet',
      body: 'The async search lands in the next ticket.',
    );
  }

  static const _prompts = [
    '\u201cCowok min 180 cm, suka hiking, serius cari pasangan\u201d',
    '\u201cWoman in South Jakarta who reads a lot and loves coffee\u201d',
    '\u201cSomeone into gaming and padel, INTJ or INFJ\u201d',
  ];
}

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Material(
      color: c.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            text,
            style: TextStyle(fontSize: 14, height: 1.4, color: c.text),
          ),
        ),
      ),
    );
  }
}
