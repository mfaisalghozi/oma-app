import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/describe_results.dart';
import 'describe_controller.dart';

/// Saved results for one search. Reloads are free: the search is already paid.
final describeResultsProvider = FutureProvider.family<DescribeResults, String>((
  ref,
  searchId,
) {
  return ref.watch(describeRepositoryProvider).results(searchId);
});
