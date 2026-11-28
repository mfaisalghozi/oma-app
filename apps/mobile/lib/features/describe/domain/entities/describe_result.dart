import 'package:meta/meta.dart';

import '../../../discover/domain/entities/deck_card.dart';
import 'describe_criteria.dart';

@immutable
class CriterionEvaluation {
  const CriterionEvaluation({
    required this.field,
    required this.mandatory,
    required this.status,
    this.evidence,
  });

  factory CriterionEvaluation.fromJson(Map<String, Object?> json) =>
      CriterionEvaluation(
        field: json['field'] as String? ?? '',
        mandatory: json['mandatory'] as bool? ?? false,
        status: json['status'] as String? ?? 'not_matched',
        evidence: json['evidence'] as String?,
      );

  final String field;
  final bool mandatory;
  final String status;
  final String? evidence;
}

@immutable
class DescribeViolation {
  const DescribeViolation({required this.criterion, this.deviation});

  factory DescribeViolation.fromJson(Map<String, Object?> json) =>
      DescribeViolation(
        criterion: json['criterion'] is Map
            ? Criterion.fromJson((json['criterion'] as Map).cast())
            : Criterion.fromJson(json),
        deviation: (json['deviation'] as num?)?.toInt(),
      );

  final Criterion criterion;
  final int? deviation;
}

@immutable
class DescribeResultRow {
  const DescribeResultRow({
    required this.candidate,
    required this.ordinal,
    required this.profileUpdated,
    this.tier = 'exact',
    this.matched,
    this.total,
    this.reason,
    this.violations = const [],
    this.evaluations = const [],
  });

  factory DescribeResultRow.fromJson(Map<String, Object?> json) =>
      DescribeResultRow(
        candidate: DeckCard.fromJson((json['candidate'] as Map).cast()),
        ordinal: (json['ordinal'] as num?)?.toInt() ?? 0,
        profileUpdated: json['profile_updated'] as bool? ?? false,
        tier: json['tier'] as String? ?? 'exact',
        matched: (json['matched'] as num?)?.toInt(),
        total: (json['total'] as num?)?.toInt(),
        reason: json['reason'] as String?,
        violations: [
          for (final item in (json['violated_criteria'] as List? ?? const []))
            DescribeViolation.fromJson((item as Map).cast()),
        ],
        evaluations: [
          for (final item
              in (json['criterion_evaluations'] as List? ?? const []))
            CriterionEvaluation.fromJson((item as Map).cast()),
        ],
      );

  final DeckCard candidate;
  final int ordinal;
  final bool profileUpdated;
  final String tier;
  final int? matched;
  final int? total;
  final String? reason;
  final List<DescribeViolation> violations;
  final List<CriterionEvaluation> evaluations;

  bool get isClose => tier == 'close';
}
