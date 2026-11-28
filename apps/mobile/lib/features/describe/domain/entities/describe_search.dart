import 'package:meta/meta.dart';

import 'describe_criteria.dart';

enum DescribeStatus {
  queued,
  parsing,
  retrieving,
  ranking,
  succeeded,
  failed;

  static DescribeStatus parse(Object? value) => switch (value) {
    'queued' => DescribeStatus.queued,
    'parsing' => DescribeStatus.parsing,
    'retrieving' => DescribeStatus.retrieving,
    'ranking' => DescribeStatus.ranking,
    'succeeded' => DescribeStatus.succeeded,
    _ => DescribeStatus.failed,
  };

  bool get isTerminal => this == succeeded || this == failed;
}

/// One async search. `/v1/describe/searches` returns it on create and on every
/// status poll.
@immutable
class DescribeSearch {
  const DescribeSearch({
    required this.id,
    required this.status,
    this.criteria,
    this.errorCode,
    this.createdAt,
    this.pollAfterSeconds = 2,
  });

  factory DescribeSearch.fromJson(Map<String, Object?> json) => DescribeSearch(
    id: json['search_id'] as String? ?? '',
    status: DescribeStatus.parse(json['status']),
    criteria: json['criteria'] == null
        ? null
        : DescribeCriteria.fromJson((json['criteria'] as Map).cast()),
    errorCode: json['error_code'] as String?,
    createdAt: json['created_at'] is String
        ? DateTime.tryParse(json['created_at']! as String)
        : null,
    pollAfterSeconds: (json['poll_after_seconds'] as num?)?.toInt() ?? 2,
  );

  final String id;
  final DescribeStatus status;
  final DescribeCriteria? criteria;
  final String? errorCode;
  final DateTime? createdAt;
  final int pollAfterSeconds;

  bool get failed => status == DescribeStatus.failed;

  DescribeSearch copyWith({
    DescribeStatus? status,
    DescribeCriteria? criteria,
  }) => DescribeSearch(
    id: id,
    status: status ?? this.status,
    criteria: criteria ?? this.criteria,
    errorCode: errorCode,
    createdAt: createdAt,
    pollAfterSeconds: pollAfterSeconds,
  );
}
