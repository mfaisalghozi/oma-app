import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../../auth/application/session_controller.dart';
import '../data/api_consent_repository.dart';
import '../domain/entities/consent_document.dart';
import '../domain/repositories/consent_repository.dart';

final consentRepositoryProvider = Provider<ConsentRepository>(
  (ref) => ApiConsentRepository(ref.watch(apiClientProvider)),
);

class ConsentState {
  const ConsentState({
    required this.documents,
    this.ticked = const {},
    this.saving = false,
    this.error,
  });

  final List<ConsentDocument> documents;
  final Set<String> ticked;
  final bool saving;

  /// Last save error. Ticks are kept.
  final Failure? error;

  bool get canContinue =>
      !saving &&
      documents.isNotEmpty &&
      documents.where((d) => d.required).every((d) => ticked.contains(d.type));

  ConsentState copyWith({
    Set<String>? ticked,
    bool? saving,
    Failure? error,
    bool clearError = false,
  }) => ConsentState(
    documents: documents,
    ticked: ticked ?? this.ticked,
    saving: saving ?? this.saving,
    error: clearError ? null : error ?? this.error,
  );
}

/// M05. Consent is saved before any sensitive field leaves the phone; after
/// it is saved the session re-reads `next_action` and the gates open M06.
class ConsentController extends AsyncNotifier<ConsentState> {
  @override
  Future<ConsentState> build() async {
    final docs = await ref.watch(consentRepositoryProvider).activeDocuments();
    return ConsentState(documents: docs);
  }

  void toggle(String type) {
    final s = state.value;
    if (s == null || s.saving) return;
    final ticked = {...s.ticked};
    ticked.contains(type) ? ticked.remove(type) : ticked.add(type);
    state = AsyncData(s.copyWith(ticked: ticked, clearError: true));
  }

  Future<void> submit() async {
    final s = state.value;
    if (s == null || !s.canContinue) return;
    state = AsyncData(s.copyWith(saving: true, clearError: true));
    try {
      await ref.read(consentRepositoryProvider).accept(s.ticked);
      await ref.read(sessionControllerProvider.notifier).refresh();
      state = AsyncData(s.copyWith(saving: false, clearError: true));
    } on Failure catch (e) {
      state = AsyncData(s.copyWith(saving: false, error: e));
    }
  }
}

final consentControllerProvider =
    AsyncNotifierProvider.autoDispose<ConsentController, ConsentState>(
      ConsentController.new,
      retry: (_, _) => null,
    );
