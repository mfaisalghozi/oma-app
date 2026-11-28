import 'package:meta/meta.dart';

import 'describe_criteria.dart';
import 'describe_result.dart';

/// The saved outcome of one successful search.
@immutable
class DescribeResults {
  const DescribeResults({
    required this.searchId,
    required this.criteria,
    required this.rows,
  });

  factory DescribeResults.fromJson(Map<String, Object?> json) =>
      DescribeResults(
        searchId: json['search_id'] as String? ?? '',
        criteria: json['criteria'] == null
            ? const DescribeCriteria(originalQuery: '')
            : DescribeCriteria.fromJson((json['criteria'] as Map).cast()),
        rows: [
          for (final item in (json['results'] as List? ?? const []))
            DescribeResultRow.fromJson((item as Map).cast()),
        ],
      );

  final String searchId;
  final DescribeCriteria criteria;
  final List<DescribeResultRow> rows;

  bool get isEmpty => rows.isEmpty;
}
