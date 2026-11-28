import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../../usage/application/usage_providers.dart';
import '../data/api_describe_repository.dart';
import '../domain/entities/describe_criteria.dart';
import '../domain/entities/describe_search.dart';
import '../domain/repositories/describe_repository.dart';

enum DescribeStage { idle, submitting, analyzing, done, failed, limitReached }

@immutable
class DescribeState {
  const DescribeState({
    this.draft = '',
    this.stage = DescribeStage.idle,
    this.search,
    this.error,
    this.errorCode,
    this.timedOut = false,
    this.lastSuccessSearchId,
    this.lastFailedSearchId,
  });

  final String draft;
  final DescribeStage stage;
  final DescribeSearch? search;
  final Object? error;
  final String? errorCode;

  /// The 45 s client deadline passed while the search was still running.
  final bool timedOut;

  /// Memory only: no `/latest`, so See my last results dies with the process.
  final String? lastSuccessSearchId;
  final String? lastFailedSearchId;

  DescribeCriteria? get criteria => search?.criteria;

  DescribeState copyWith({
    String? draft,
    DescribeStage? stage,
    DescribeSearch? search,
    Object? error,
    String? errorCode,
    bool? timedOut,
    bool clearError = false,
    String? lastSuccessSearchId,
    String? lastFailedSearchId,
  }) => DescribeState(
    draft: draft ?? this.draft,
    stage: stage ?? this.stage,
    search: search ?? this.search,
    error: clearError ? null : (error ?? this.error),
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    timedOut: timedOut ?? this.timedOut,
    lastSuccessSearchId: lastSuccessSearchId ?? this.lastSuccessSearchId,
    lastFailedSearchId: lastFailedSearchId ?? this.lastFailedSearchId,
  );
}

final describeRepositoryProvider = Provider<DescribeRepository>(
  (ref) => ApiDescribeRepository(ref.watch(apiClientProvider)),
);

class DescribeController extends Notifier<DescribeState> {
  static const deadline = Duration(seconds: 45);

  Timer? _poll;

  @override
  DescribeState build() {
    ref.onDispose(() => _poll?.cancel());
    return const DescribeState();
  }

  void setDraft(String value) => state = state.copyWith(draft: value);

  void openLastResults(String searchId) {
    // The results route lands with DSB-FE-03.
  }

  Future<void> submit() async {
    final query = state.draft.trim();
    if (query.length < 3) return;
    state = state.copyWith(
      stage: DescribeStage.submitting,
      clearError: true,
      timedOut: false,
    );
    try {
      final search = await ref
          .read(describeRepositoryProvider)
          .create(query: query, idempotencyKey: const Uuid().v4());
      state = state.copyWith(stage: DescribeStage.analyzing, search: search);
      _startPolling(search);
      unawaited(ref.read(dailyUsageProvider.notifier).refresh());
    } on ApiFailure catch (failure) {
      switch (failure.code) {
        case ApiErrorCode.searchQuotaExhausted:
          state = state.copyWith(stage: DescribeStage.limitReached);
          unawaited(ref.read(dailyUsageProvider.notifier).refresh());
        case ApiErrorCode.searchInProgress:
          state = state.copyWith(
            stage: DescribeStage.failed,
            errorCode: failure.code,
          );
        case ApiErrorCode.describeNotConfigured:
          state = state.copyWith(
            stage: DescribeStage.failed,
            errorCode: failure.code,
          );
        default:
          state = state.copyWith(
            stage: DescribeStage.failed,
            error: failure,
            errorCode: failure.code,
          );
      }
    } on NetworkFailure catch (failure) {
      state = state.copyWith(stage: DescribeStage.failed, error: failure);
    }
  }

  /// Try again opens a new search that names the failed one.
  Future<void> retry() async {
    final failed = state.lastFailedSearchId;
    final query = state.draft.trim();
    if (query.length < 3) return;
    state = state.copyWith(
      stage: DescribeStage.submitting,
      clearError: true,
      timedOut: false,
    );
    try {
      final search = await ref
          .read(describeRepositoryProvider)
          .create(
            query: query,
            retryOf: failed,
            idempotencyKey: const Uuid().v4(),
          );
      state = state.copyWith(stage: DescribeStage.analyzing, search: search);
      _startPolling(search);
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        stage: DescribeStage.failed,
        errorCode: failure.code,
      );
    } on NetworkFailure catch (failure) {
      state = state.copyWith(stage: DescribeStage.failed, error: failure);
    }
  }

  void _startPolling(DescribeSearch search) {
    _poll?.cancel();
    final started = DateTime.now();
    _pollOnce(search.id, started, search.pollAfterSeconds);
  }

  Future<void> _pollOnce(String id, DateTime started, int seconds) async {
    if (DateTime.now().difference(started) >= deadline) {
      state = state.copyWith(stage: DescribeStage.failed, timedOut: true);
      return;
    }
    await Future<void>.delayed(Duration(seconds: seconds));
    if (state.stage != DescribeStage.analyzing) return;
    try {
      final search = await ref.read(describeRepositoryProvider).status(id);
      if (search.failed) {
        state = state.copyWith(
          stage: DescribeStage.failed,
          search: search,
          errorCode: search.errorCode,
          lastFailedSearchId: id,
        );
        return;
      }
      state = state.copyWith(search: search);
      if (search.status == DescribeStatus.succeeded) {
        state = state.copyWith(
          stage: DescribeStage.done,
          lastSuccessSearchId: id,
        );
        unawaited(ref.read(dailyUsageProvider.notifier).refresh());
        return;
      }
      await _pollOnce(id, started, search.pollAfterSeconds);
    } on NetworkFailure {
      // Keep polling until the deadline; a dropped poll is not a failed search.
      await _pollOnce(id, started, seconds);
    } on ApiFailure catch (failure) {
      if (failure.code == ApiErrorCode.notFound) {
        state = state.copyWith(
          stage: DescribeStage.failed,
          errorCode: failure.code,
        );
        return;
      }
      await _pollOnce(id, started, seconds);
    }
  }
}

final describeControllerProvider =
    NotifierProvider<DescribeController, DescribeState>(DescribeController.new);
