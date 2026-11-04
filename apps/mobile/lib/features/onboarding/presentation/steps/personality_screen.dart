import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../../../core/widgets/oma_chip.dart';
import '../../../../core/widgets/oma_field.dart';
import '../../application/master_data_providers.dart';
import '../../application/onboarding_draft_controller.dart';
import '../../domain/entities/master_option.dart';
import '../../domain/entities/onboarding_draft.dart';
import '../../domain/entities/onboarding_step.dart';
import '../widgets/draft_builder.dart';
import '../widgets/master_chips.dart';
import '../widgets/option_picker.dart';
import '../widgets/step_frame.dart';

/// Design v0.1 says 80; the BE allows 500. The stricter client limit is safe.
const ambitionMaxLength = 80;

class PersonalityScreen extends StatelessWidget {
  const PersonalityScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      DraftBuilder(builder: (_, draft) => _PersonalityForm(initial: draft));
}

class _PersonalityForm extends ConsumerStatefulWidget {
  const _PersonalityForm({required this.initial});

  final OnboardingDraft initial;

  @override
  ConsumerState<_PersonalityForm> createState() => _PersonalityFormState();
}

class _PersonalityFormState extends ConsumerState<_PersonalityForm> {
  late final _ambition = TextEditingController(text: widget.initial.ambition);

  @override
  void dispose() {
    _ambition.dispose();
    super.dispose();
  }

  OnboardingDraftController get _draft =>
      ref.read(onboardingDraftProvider.notifier);

  Future<void> _toggleHobby(MasterOption hobby) async {
    ref.read(pickedLabelsProvider.notifier).remember([hobby]);
    await _draft.edit((d) {
      final ids = [...d.hobbyIds];
      ids.contains(hobby.id) ? ids.remove(hobby.id) : ids.add(hobby.id);
      return d.copyWith(hobbyIds: ids);
    });
  }

  Future<void> _search(Set<String> selected, {MasterOption? category}) async {
    final picked = await SearchPickerSheet.show(
      context,
      title: category?.label ?? 'Hobbies',
      type: MasterDataType.hobby,
      categoryId: category?.id,
      selectedIds: selected,
    );
    if (picked != null) await _toggleHobby(picked);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider).value ?? widget.initial;
    final selected = draft.hobbyIds.toSet();
    final categories = ref.watch(
      masterOptionsProvider(MasterDataType.hobbyCategory),
    );

    return StepFrame(
      step: OnboardingStep.personality,
      title: 'Personality and hobbies',
      subtitle: 'Pick what fits. People can comment on any hobby you add.',
      canContinue: draft.personalityDone,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OmaField(
            label: 'Ambition',
            controller: _ambition,
            placeholder: 'Optional',
            maxLength: ambitionMaxLength,
            maxLines: 2,
            showCounter: true,
            onChanged: (v) => _draft.editTyping(
              (d) => d.copyWith(ambition: Nullable(v.trim())),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OptionPickerField(
                  label: 'Religion',
                  type: MasterDataType.religion,
                  selectedId: draft.religionId,
                  placeholder: 'Optional',
                  onChanged: (o) => _draft.edit(
                    (d) => d.copyWith(religionId: Nullable(o?.id)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OptionPickerField(
                  label: 'Personality',
                  type: MasterDataType.personality,
                  selectedId: draft.personalityTypeId,
                  placeholder: 'e.g. INFJ',
                  onChanged: (o) => _draft.edit(
                    (d) => d.copyWith(personalityTypeId: Nullable(o?.id)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          StepLabel(
            'Hobbies',
            trailing: TextButton.icon(
              onPressed: () => _search(selected),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Search'),
            ),
          ),
          switch (categories) {
            AsyncData(value: final cats) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final cat in cats)
                  _HobbyGroup(
                    category: cat,
                    selected: selected,
                    onToggle: _toggleHobby,
                    onMore: () => _search(selected, category: cat),
                  ),
                _OtherPicks(selected: selected, onToggle: _toggleHobby),
              ],
            ),
            AsyncError() => MasterLoadError(
              onRetry: () => ref.invalidate(
                masterOptionsProvider(MasterDataType.hobbyCategory),
              ),
            ),
            _ => const ChipsLoading(),
          },
        ],
      ),
    );
  }
}

class _HobbyGroup extends ConsumerWidget {
  const _HobbyGroup({
    required this.category,
    required this.selected,
    required this.onToggle,
    required this.onMore,
  });

  final MasterOption category;
  final Set<String> selected;
  final ValueChanged<MasterOption> onToggle;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.oma;
    final page = ref.watch(hobbiesByCategoryProvider(category.id));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            category.label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: 8),
          switch (page) {
            AsyncData(:final value) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final h in value.items)
                  OmaChoiceChip(
                    label: h.label,
                    selected: selected.contains(h.id),
                    onTap: () => onToggle(h),
                  ),
                if (value.hasMore)
                  OmaChoiceChip(label: 'More…', selected: false, onTap: onMore),
              ],
            ),
            AsyncError() => MasterLoadError(
              onRetry: () =>
                  ref.invalidate(hobbiesByCategoryProvider(category.id)),
            ),
            _ => const ChipsLoading(),
          },
        ],
      ),
    );
  }
}

class _OtherPicks extends ConsumerWidget {
  const _OtherPicks({required this.selected, required this.onToggle});

  final Set<String> selected;
  final ValueChanged<MasterOption> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = <String>{};
    final cats =
        ref.watch(masterOptionsProvider(MasterDataType.hobbyCategory)).value ??
        const [];
    for (final cat in cats) {
      final items = ref.watch(hobbiesByCategoryProvider(cat.id)).value?.items;
      shown.addAll(items?.map((h) => h.id) ?? const []);
    }
    final labels = ref.watch(pickedLabelsProvider);
    final extra = selected.difference(shown);
    if (extra.isEmpty) return const SizedBox.shrink();
    final named = extra.where(labels.containsKey).toList();
    final unnamed = extra.length - named.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepLabel('Your other picks'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in named)
              OmaChoiceChip(
                label: labels[id]!,
                selected: true,
                onTap: () => onToggle(MasterOption(id: id, label: labels[id]!)),
              ),
          ],
        ),
        if (unnamed > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '+$unnamed more picked',
              style: TextStyle(color: context.oma.textMuted),
            ),
          ),
      ],
    );
  }
}
