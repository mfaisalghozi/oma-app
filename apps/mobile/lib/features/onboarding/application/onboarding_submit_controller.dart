import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../../auth/application/session_controller.dart';
import '../data/api_onboarding_repository.dart';
import '../domain/entities/onboarding_draft.dart';
import '../domain/entities/onboarding_step.dart';
import '../domain/repositories/onboarding_repository.dart';
import '../domain/usecases/onboarding_payload.dart';
import 'onboarding_draft_controller.dart';
import 'photo_grid_controller.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => ApiOnboardingRepository(ref.watch(apiClientProvider)),
);

/// The three M11b lines, in order.
enum SetupPhase { saving, photos, finding }

enum PhaseStatus { waiting, running, done, failed }

@immutable
sealed class SubmitState {
  const SubmitState();
}

final class SubmitIdle extends SubmitState {
  const SubmitIdle();
}

final class SubmitRunning extends SubmitState {
  const SubmitRunning(this.phase);

  final SetupPhase phase;
}

/// M11c. The draft is untouched; Try again repeats the same call.
final class SubmitFailed extends SubmitState {
  const SubmitFailed(this.phase, this.error);

  final SetupPhase phase;
  final Failure error;
}

/// 422: send the user to the step that owns the field, answers kept.
final class SubmitNeedsFix extends SubmitState {
  const SubmitNeedsFix(this.step, this.fields);

  final OnboardingStep step;
  final List<String> fields;
}

final class SubmitDone extends SubmitState {
  const SubmitDone();
}

extension SubmitPhases on SubmitState {
  PhaseStatus statusOf(SetupPhase p) => switch (this) {
    SubmitRunning(:final phase) ||
    SubmitFailed(:final phase) when p.index < phase.index => PhaseStatus.done,
    SubmitRunning(:final phase) when p == phase => PhaseStatus.running,
    SubmitFailed(:final phase) when p == phase => PhaseStatus.failed,
    SubmitDone() => PhaseStatus.done,
    _ => PhaseStatus.waiting,
  };
}

/// M11b: one `POST /v1/me/onboarding` with the whole draft.
class OnboardingSubmitController extends Notifier<SubmitState> {
  @override
  SubmitState build() => const SubmitIdle();

  bool get _busy => state is SubmitRunning;

  static const _validation = {
    ApiErrorCode.onboardingValidationFailed,
    ApiErrorCode.userUnder18,
    ApiErrorCode.invalidProfileData,
  };

  Future<void> submit() async {
    if (_busy) return;
    var phase = SetupPhase.saving;
    state = SubmitRunning(phase);
    final drafts = ref.read(onboardingDraftProvider.notifier);
    try {
      await ref.read(sessionControllerProvider.future);
      if (await ref.read(onboardingDraftProvider.future) == null) {
        throw const UnexpectedFailure('no draft');
      }
      // One key per submission, saved first so a kill + reopen reuses it.
      if (ref.read(onboardingDraftProvider).value?.submitKey == null) {
        await drafts.edit(
          (d) => d.copyWith(submitKey: Nullable(const Uuid().v4())),
        );
      }
      await drafts.flush();

      phase = SetupPhase.photos;
      state = SubmitRunning(phase);
      await _finishUploads();
      final draft = ref.read(onboardingDraftProvider).value!;
      try {
        await ref
            .read(onboardingRepositoryProvider)
            .submit(onboardingPayload(draft), idempotencyKey: draft.submitKey!);
      } on ApiFailure catch (e) {
        // 409: an earlier attempt went through; carry on to Discover.
        if (e.code != ApiErrorCode.onboardingAlreadyCompleted) rethrow;
      }

      phase = SetupPhase.finding;
      state = SubmitRunning(phase);
      await drafts.clear();
      ref.invalidate(photoGridProvider);
      // TODO(discover): prefetch the first deck here once the deck API is
      // specified; for now the session refresh moves the gate to M12.
      state = const SubmitDone();
      await ref.read(sessionControllerProvider.notifier).refresh();
    } on ApiFailure catch (e) {
      if (!_validation.contains(e.code)) {
        state = SubmitFailed(phase, e);
        return;
      }
      final fields = e.fieldErrors.map((f) => f.field).toList();
      final step = e.code == ApiErrorCode.userUnder18
          ? OnboardingStep.basics
          : fields.isEmpty
          ? OnboardingStep.basics
          : fields
                .map(stepForField)
                .reduce((a, b) => a.index <= b.index ? a : b);
      state = SubmitNeedsFix(step, fields);
    } on Failure catch (e) {
      state = SubmitFailed(phase, e);
    } on Object catch (e) {
      state = SubmitFailed(phase, UnexpectedFailure('$e'));
    }
  }

  /// Retries photos that aren't uploaded yet. Fails if none is uploaded.
  Future<void> _finishUploads() async {
    final grid = ref.read(photoGridProvider.notifier);
    final pending = [
      for (final p in ref.read(onboardingDraftProvider).value!.photos)
        if (!p.isUploaded) p.localPath,
    ];
    for (final key in pending) {
      await grid.retry(key);
    }
    final photos = ref.read(onboardingDraftProvider).value!.photos;
    if (photos.any((p) => !p.isUploaded)) {
      throw const NetworkFailure('photo upload pending');
    }
  }
}

final onboardingSubmitProvider =
    NotifierProvider<OnboardingSubmitController, SubmitState>(
      OnboardingSubmitController.new,
    );
