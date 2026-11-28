import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

@immutable
class DescribeState {
  const DescribeState({this.draft = '', this.lastSuccessSearchId});

  final String draft;

  /// Held in memory only: there is no `/latest`, so See my last results is
  /// hidden after a restart (SA section 5).
  final String? lastSuccessSearchId;

  DescribeState copyWith({String? draft, String? lastSuccessSearchId}) =>
      DescribeState(
        draft: draft ?? this.draft,
        lastSuccessSearchId: lastSuccessSearchId ?? this.lastSuccessSearchId,
      );
}

class DescribeController extends Notifier<DescribeState> {
  @override
  DescribeState build() => const DescribeState();

  void setDraft(String value) {
    state = state.copyWith(draft: value);
  }

  void rememberSuccess(String searchId) {
    state = state.copyWith(lastSuccessSearchId: searchId);
  }

  void openLastResults(String searchId) {
    // Navigation lands with DSB-FE-03, which owns the results route.
  }
}

final describeControllerProvider =
    NotifierProvider<DescribeController, DescribeState>(DescribeController.new);
