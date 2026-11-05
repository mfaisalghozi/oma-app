import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/oma_colors.dart';
import '../../../../core/widgets/oma_banner.dart';
import '../../../../core/widgets/oma_button.dart';
import '../../../../core/widgets/oma_chip.dart';
import '../../../device/application/device_registrar.dart';
import '../../../device/domain/location_service.dart';
import '../../application/onboarding_draft_controller.dart';
import '../../application/onboarding_resume.dart';
import '../../domain/entities/city.dart';
import '../../domain/entities/onboarding_draft.dart';
import '../../domain/entities/onboarding_step.dart';
import '../widgets/draft_builder.dart';
import '../widgets/step_frame.dart';

class LocationScreen extends StatelessWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      DraftBuilder(builder: (_, draft) => _LocationBody(initial: draft));
}

class _LocationBody extends ConsumerStatefulWidget {
  const _LocationBody({required this.initial});

  final OnboardingDraft initial;

  @override
  ConsumerState<_LocationBody> createState() => _LocationBodyState();
}

class _LocationBodyState extends ConsumerState<_LocationBody>
    with WidgetsBindingObserver {
  bool _denied = false;
  bool _busy = false;
  bool _fixFailed = false;
  late City _city = fallbackCities.firstWhere(
    (c) => c.name == widget.initial.location?.cityName,
    orElse: () => fallbackCities.first,
  );

  LocationService get _location => ref.read(locationServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _denied = widget.initial.location?.source == LocationSource.city;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _denied) {
      _location.status().then((s) {
        if (s == LocationAccess.granted && mounted) _takeFix();
      });
    }
  }

  Future<void> _allow() async {
    setState(() => _busy = true);
    final access = await _location.request();
    if (!mounted) return;
    if (access == LocationAccess.granted) return _takeFix();
    setState(() {
      _busy = false;
      _denied = true;
    });
  }

  Future<void> _takeFix() async {
    setState(() {
      _busy = true;
      _fixFailed = false;
    });
    try {
      final fix = await _location.currentFix();
      await _save(
        DraftLocation(
          latitude: roundCoordinate(fix.latitude),
          longitude: roundCoordinate(fix.longitude),
          source: LocationSource.gps,
        ),
      );
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _denied = true;
          _fixFailed = true;
        });
      }
    }
  }

  Future<void> _useCity() => _save(
    DraftLocation(
      latitude: _city.latitude,
      longitude: _city.longitude,
      source: LocationSource.city,
      cityName: _city.name,
    ),
  );

  Future<void> _save(DraftLocation location) async {
    await ref
        .read(onboardingDraftProvider.notifier)
        .edit((d) => d.copyWith(location: Nullable(location)));
    if (mounted) context.go(nextStepPath(OnboardingStep.location));
  }

  @override
  Widget build(BuildContext context) =>
      _denied ? _deniedView(context) : _askView(context);

  Widget _askView(BuildContext context) {
    final c = context.oma;
    return StepFrame(
      step: OnboardingStep.location,
      title: 'Find people near you',
      subtitle:
          "We use your rough location to show who's nearby. Your exact spot "
          'never leaves our servers; others see distance only, like “4 km '
          'away”.',
      canContinue: !_busy,
      nextLabel: 'Allow location',
      onNext: _allow,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(color: c.mint, shape: BoxShape.circle),
              child: Icon(Icons.near_me_outlined, size: 52, color: c.primary),
            ),
          ),
          const SizedBox(height: 28),
          const _Point(
            icon: Icons.straighten,
            text: 'Distance is rounded to the nearest km',
          ),
          const SizedBox(height: 12),
          const _Point(icon: Icons.map_outlined, text: 'Never shown on a map'),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OmaButton.text(
          label: 'Not now',
          onPressed: _busy ? null : () => setState(() => _denied = true),
        ),
      ),
    );
  }

  Widget _deniedView(BuildContext context) {
    return StepFrame(
      step: OnboardingStep.location,
      title: 'Location is off',
      subtitle:
          'OMA needs your rough location to show people near you. Others '
          'only ever see a distance like “4 km away”.',
      canContinue: !_busy,
      nextLabel: 'Open phone settings',
      onNext: _location.openSettings,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_fixFailed) ...[
            const OmaBanner(
              message: "We couldn't get your location. Pick your city instead.",
            ),
            const SizedBox(height: 16),
          ],
          const StepLabel('Or pick your city'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final city in fallbackCities)
                OmaChoiceChip(
                  label: city.name,
                  selected: city == _city,
                  onTap: () => setState(() => _city = city),
                ),
            ],
          ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OmaButton.secondary(
          label: 'Use ${_city.name}',
          onPressed: _busy ? null : _useCity,
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.oma;
    return Row(
      children: [
        Icon(icon, color: c.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }
}
