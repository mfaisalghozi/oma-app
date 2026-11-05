import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/oma_field.dart';
import '../../application/onboarding_draft_controller.dart';
import '../../application/today.dart';
import '../../domain/entities/master_option.dart';
import '../../domain/entities/onboarding_draft.dart';
import '../../domain/entities/onboarding_step.dart';
import '../widgets/draft_builder.dart';
import '../widgets/master_chips.dart';
import '../widgets/step_frame.dart';
import '../widgets/tap_field.dart';

class BasicsScreen extends StatelessWidget {
  const BasicsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      DraftBuilder(builder: (_, draft) => _BasicsForm(initial: draft));
}

class _BasicsForm extends ConsumerStatefulWidget {
  const _BasicsForm({required this.initial});

  final OnboardingDraft initial;

  @override
  ConsumerState<_BasicsForm> createState() => _BasicsFormState();
}

class _BasicsFormState extends ConsumerState<_BasicsForm> {
  late final _name = TextEditingController(text: widget.initial.fullName);

  /// An under-18 pick is shown but never saved to the draft.
  DateTime? _underage;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  OnboardingDraftController get _draft =>
      ref.read(onboardingDraftProvider.notifier);

  Future<void> _pickBirthdate(DateTime? current) async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate:
          current ??
          _underage ??
          DateTime(today.year - 25, today.month, today.day),
      firstDate: DateTime(today.year - 100),
      lastDate: today,
      helpText: 'Birthdate',
    );
    if (picked == null) return;
    final adult = ageOn(picked, today) >= minimumAge;
    setState(() => _underage = adult ? null : picked);
    await _draft.edit(
      (d) => d.copyWith(birthdate: Nullable(adult ? picked : null)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider).value ?? widget.initial;
    final birthdate = _underage ?? draft.birthdate;
    final nameLength = _name.text.trim().length;

    return StepFrame(
      step: OnboardingStep.basics,
      title: 'The basics',
      canContinue: draft.basicsDone && _underage == null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OmaField(
            label: 'First name',
            controller: _name,
            hint: 'This is how you appear on OMA.',
            errorText: nameLength == 1 ? 'Use at least 2 characters.' : null,
            maxLength: 100,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.givenName],
            onChanged: (v) {
              setState(() {});
              _draft.editTyping(
                (d) => d.copyWith(fullName: Nullable(v.trim())),
              );
            },
          ),
          const SizedBox(height: 20),
          TapField(
            label: 'Birthdate',
            value: birthdate == null ? null : formatDate(birthdate),
            placeholder: 'DD Month YYYY',
            icon: Icons.calendar_today_outlined,
            hint: "Shown as your age only. You can't change it later.",
            errorText: _underage == null
                ? null
                : 'You need to be 18 or older to use OMA.',
            onTap: () => _pickBirthdate(draft.birthdate),
          ),
          const SizedBox(height: 24),
          const StepLabel('I am'),
          MasterChips(
            type: MasterDataType.gender,
            selected: {?draft.genderId},
            onChanged: (ids) =>
                _draft.edit((d) => d.copyWith(genderId: Nullable(ids.first))),
          ),
          const SizedBox(height: 24),
          const StepLabel('Show me'),
          MasterChips(
            type: MasterDataType.showMe,
            selected: {?draft.showMeOptionId},
            onChanged: (ids) => _draft.edit(
              (d) => d.copyWith(showMeOptionId: Nullable(ids.first)),
            ),
          ),
        ],
      ),
    );
  }
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// TODO(l10n): replace with intl `DateFormat` when ARB lands.
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
