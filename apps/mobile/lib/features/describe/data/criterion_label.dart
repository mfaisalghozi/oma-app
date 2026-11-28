import '../domain/entities/describe_criteria.dart';
import '../domain/entities/describe_result.dart';

/// Chip and row copy is built by the FE, not sent by the server (SA section 5).
abstract final class CriterionLabel {
  static const _catalogFields = {
    'gender',
    'religion',
    'university',
    'personality',
    'hobby',
    'hobbies',
    'looking_for',
  };

  static String of(Criterion criterion) {
    final field = criterion.field;
    final number = criterion.number;
    final operator = criterion.operator;
    if (field == 'height_cm' && number != null) {
      if (operator == 'lte') return 'Up to $number cm';
      if (operator == 'eq') return '$number cm';
      return '$number cm+';
    }
    if (field == 'age' && number != null) {
      if (operator == 'lte') return 'Up to $number';
      if (operator == 'eq') return 'Age $number';
      return '$number+';
    }
    if (field == 'distance_km' && number != null) {
      return 'Within $number km';
    }
    if (field == 'bio' || field == 'ambition') {
      final text = criterion.text ?? criterion.evidence ?? '';
      return 'Mentions $text';
    }
    if (_catalogFields.contains(field)) {
      return criterion.text ?? criterion.evidence ?? field;
    }
    final text = criterion.text ?? criterion.evidence;
    if (text != null) return text;
    if (number != null) return '$number';
    return field;
  }

  static String notSearchable(NotSearchable item) => item.text;

  /// `2 cm under your minimum`, `1 year outside your range`,
  /// `3 km further than you asked` — close rows only.
  static String? closeReason(DescribeResultRow row) {
    for (final violation in row.violations) {
      final deviation = violation.deviation;
      final field = violation.criterion.field;
      if (deviation == null || deviation == 0) continue;
      return switch (field) {
        'height_cm' => '$deviation cm under your minimum',
        'age' =>
          '$deviation ${deviation == 1 ? 'year' : 'years'} outside your range',
        'distance_km' => '$deviation km further than you asked',
        _ => null,
      };
    }
    return null;
  }
}
