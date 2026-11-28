import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/describe/application/describe_controller.dart';
import 'package:oma_app/features/describe/domain/entities/describe_criteria.dart';
import 'package:oma_app/features/describe/domain/entities/describe_results.dart';
import 'package:oma_app/features/describe/domain/entities/describe_search.dart';
import 'package:oma_app/features/describe/domain/repositories/describe_repository.dart';
import 'package:oma_app/features/usage/application/usage_providers.dart';

import '../../helpers/fakes.dart';

class _FakeDescribe implements DescribeRepository {
  final List<String> created = [];
  Object? createError;
  DescribeSearch search = const DescribeSearch(
    id: 's1',
    status: DescribeStatus.queued,
  );

  @override
  Future<DescribeSearch> create({
    required String query,
    String? retryOf,
    required String idempotencyKey,
  }) async {
    created.add(query);
    final failure = createError;
    if (failure != null) throw failure;
    return search;
  }

  @override
  Future<DescribeSearch> status(String searchId) async => search;

  @override
  Future<DescribeResults> results(String searchId) async => DescribeResults(
    searchId: searchId,
    criteria: const DescribeCriteria(originalQuery: ''),
    rows: const [],
  );
}

void main() {
  late _FakeDescribe repository;

  setUp(() => repository = _FakeDescribe());

  ProviderContainer make() => ProviderContainer(
    overrides: [
      describeRepositoryProvider.overrideWithValue(repository),
      usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
    ],
  );

  test('a trimmed query starts the search and moves to analyzing', () async {
    final container = make();
    addTearDown(container.dispose);
    final notifier = container.read(describeControllerProvider.notifier);

    notifier.setDraft('  Male, min 180cm  ');
    await notifier.submit();

    expect(repository.created.single, 'Male, min 180cm');
    final state = container.read(describeControllerProvider);
    expect(state.stage, DescribeStage.analyzing);
    expect(state.search?.id, 's1');
  });

  test('under three characters never calls the server', () async {
    final container = make();
    addTearDown(container.dispose);
    final notifier = container.read(describeControllerProvider.notifier)
      ..setDraft('ab');

    await notifier.submit();

    expect(repository.created, isEmpty);
    expect(
      container.read(describeControllerProvider).stage,
      DescribeStage.idle,
    );
  });

  test('a spent quota becomes the limit state', () async {
    repository.createError = const ApiFailure(
      code: ApiErrorCode.searchQuotaExhausted,
      statusCode: 429,
    );
    final container = make();
    addTearDown(container.dispose);
    final notifier = container.read(describeControllerProvider.notifier)
      ..setDraft('someone kind');

    await notifier.submit();

    expect(
      container.read(describeControllerProvider).stage,
      DescribeStage.limitReached,
    );
  });

  test('a blocked provider is a failure, not a retry', () async {
    repository.createError = const ApiFailure(
      code: ApiErrorCode.describeNotConfigured,
      statusCode: 503,
    );
    final container = make();
    addTearDown(container.dispose);
    final notifier = container.read(describeControllerProvider.notifier)
      ..setDraft('someone kind');

    await notifier.submit();

    final state = container.read(describeControllerProvider);
    expect(state.stage, DescribeStage.failed);
    expect(state.errorCode, ApiErrorCode.describeNotConfigured);
  });
}
