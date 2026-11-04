import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/oma_field.dart';
import '../../application/onboarding_draft_controller.dart';
import '../../domain/entities/master_option.dart';
import '../../domain/entities/onboarding_draft.dart';
import '../../domain/entities/onboarding_step.dart';
import '../widgets/draft_builder.dart';
import '../widgets/master_chips.dart';
import '../widgets/option_picker.dart';
import '../widgets/step_frame.dart';
import '../widgets/tap_field.dart';

/// M07 About you: bio, looking for, height, weight, education.
class AboutYouScreen extends StatelessWidget {
  const AboutYouScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      DraftBuilder(builder: (_, draft) => _AboutForm(initial: draft));
}

class _AboutForm extends ConsumerStatefulWidget {
  const _AboutForm({required this.initial});

  final OnboardingDraft initial;

  @override
  ConsumerState<_AboutForm> createState() => _AboutFormState();
}

class _AboutFormState extends ConsumerState<_AboutForm> {
  late final _bio = TextEditingController(text: widget.initial.bio);
  late final _height = TextEditingController(
    text: widget.initial.heightCm?.toString(),
  );
  late final _weight = TextEditingController(
    text: widget.initial.weightKg?.toString(),
  );

  @override
  void dispose() {
    _bio.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  OnboardingDraftController get _draft =>
      ref.read(onboardingDraftProvider.notifier);

  static String? _rangeError(String text, int min, int max, String unit) {
    final v = int.tryParse(text);
    if (text.isEmpty || (v != null && v >= min && v <= max)) return null;
    return 'Between $min and $max $unit.';
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider).value ?? widget.initial;
    final digits = [FilteringTextInputFormatter.digitsOnly];

    return StepFrame(
      step: OnboardingStep.about,
      title: 'About you',
      canContinue: draft.aboutDone,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OmaField(
            label: 'Bio',
            controller: _bio,
            placeholder: 'A line or two about you',
            maxLength: 255,
            maxLines: 4,
            showCounter: true,
            onChanged: (v) =>
                _draft.editTyping((d) => d.copyWith(bio: Nullable(v.trim()))),
          ),
          const SizedBox(height: 16),
          const StepLabel('Looking for'),
          MasterChips(
            type: MasterDataType.lookingFor,
            multi: true,
            selected: draft.lookingForIds.toSet(),
            onChanged: (ids) =>
                _draft.edit((d) => d.copyWith(lookingForIds: ids.toList())),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OmaField(
                  label: 'Height',
                  controller: _height,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  maxLength: 3,
                  suffix: const _Unit('cm'),
                  errorText: _rangeError(_height.text, 100, 250, 'cm'),
                  onChanged: (v) {
                    setState(() {});
                    _draft.editTyping(
                      (d) => d.copyWith(heightCm: Nullable(int.tryParse(v))),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OmaField(
                  label: 'Weight',
                  controller: _weight,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  maxLength: 3,
                  suffix: const _Unit('kg'),
                  errorText: _rangeError(_weight.text, 25, 300, 'kg'),
                  onChanged: (v) {
                    setState(() {});
                    _draft.editTyping(
                      (d) => d.copyWith(weightKg: Nullable(int.tryParse(v))),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TapField(
            label: 'Education',
            value: draft.universityName,
            placeholder: 'Your university (optional)',
            icon: Icons.search,
            onTap: () async {
              final picked = await SearchPickerSheet.show(
                context,
                title: 'Education',
                type: MasterDataType.university,
                selectedIds: {?draft.universityId},
              );
              if (picked == null) return;
              await _draft.edit(
                (d) => d.copyWith(
                  universityId: Nullable(picked.id),
                  universityName: Nullable(picked.label),
                ),
              );
            },
          ),
          if (draft.universityId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _draft.edit(
                  (d) => d.copyWith(
                    universityId: const Nullable(null),
                    universityName: const Nullable(null),
                  ),
                ),
                child: const Text('Remove education'),
              ),
            ),
        ],
      ),
    );
  }
}

class _Unit extends StatelessWidget {
  const _Unit(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: Align(
      widthFactor: 1,
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}
