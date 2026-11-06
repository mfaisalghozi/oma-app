import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/oma_banner.dart';
import '../../../../core/widgets/oma_chip.dart';
import '../../application/master_data_providers.dart';
import '../../domain/entities/master_option.dart';

class MasterChips extends ConsumerWidget {
  const MasterChips({
    required this.type,
    required this.selected,
    required this.onChanged,
    this.multi = false,
    super.key,
  });

  final MasterDataType type;
  final Set<String> selected;
  final bool multi;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(masterOptionsProvider(type));
    return switch (options) {
      AsyncData(:final value) => OptionChips(
        options: value,
        selected: selected,
        multi: multi,
        onChanged: onChanged,
      ),
      AsyncError() => MasterLoadError(
        onRetry: () => ref.invalidate(masterOptionsProvider(type)),
      ),
      _ => const ChipsLoading(),
    };
  }
}

class OptionChips extends StatelessWidget {
  const OptionChips({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multi = false,
    super.key,
  });

  final List<MasterOption> options;
  final Set<String> selected;
  final bool multi;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final o in options)
        OmaChoiceChip(
          label: o.label,
          selected: selected.contains(o.id),
          onTap: () {
            if (!multi) return onChanged({o.id});
            final next = {...selected};
            next.contains(o.id) ? next.remove(o.id) : next.add(o.id);
            onChanged(next);
          },
        ),
    ],
  );
}

class MasterLoadError extends StatelessWidget {
  const MasterLoadError({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => OmaBanner(
    message: "We couldn't load these options. Your answers are kept.",
    actionLabel: 'Try again',
    onAction: onRetry,
  );
}

class ChipsLoading extends StatelessWidget {
  const ChipsLoading({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 40,
    child: Align(
      alignment: Alignment.centerLeft,
      child: SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
