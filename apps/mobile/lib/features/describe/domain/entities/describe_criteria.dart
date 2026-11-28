import 'package:meta/meta.dart';

int? _int(Object? value) => value is num ? value.toInt() : null;
String? _str(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// One parsed condition. The BE sends `operator`/`number`/`text`; the mock
/// sends `op`/`value`/`term`, so both are read.
@immutable
class Criterion {
  const Criterion({
    required this.field,
    this.operator,
    this.number,
    this.text,
    this.evidence,
  });

  factory Criterion.fromJson(Map<String, Object?> json) => Criterion(
    field: json['field'] as String? ?? '',
    operator: _str(json['operator']) ?? _str(json['op']),
    number: _int(json['number']) ?? _int(json['value']),
    text: _str(json['text']) ?? _str(json['term']),
    evidence: _str(json['evidence']),
  );

  final String field;
  final String? operator;
  final int? number;
  final String? text;
  final String? evidence;
}

@immutable
class NotSearchable {
  const NotSearchable({required this.text, this.reason});

  factory NotSearchable.fromJson(Map<String, Object?> json) => NotSearchable(
    text: json['text'] as String? ?? '',
    reason: json['reason'] as String?,
  );

  final String text;
  final String? reason;
}

@immutable
class DescribeCriteria {
  const DescribeCriteria({
    required this.originalQuery,
    this.version = 'v1',
    this.rewriteId,
    this.translationEn,
    this.must = const [],
    this.nice = const [],
    this.notSearchable = const [],
  });

  factory DescribeCriteria.fromJson(Map<String, Object?> json) =>
      DescribeCriteria(
        originalQuery: json['original_query'] as String? ?? '',
        version: json['version'] as String? ?? 'v1',
        rewriteId: json['rewrite_id'] as String?,
        translationEn: json['translation_en'] as String?,
        must: [
          for (final item in (json['must'] as List? ?? const []))
            Criterion.fromJson((item as Map).cast()),
        ],
        nice: [
          for (final item in (json['nice'] as List? ?? const []))
            Criterion.fromJson((item as Map).cast()),
        ],
        notSearchable: [
          for (final item in (json['not_searchable'] as List? ?? const []))
            NotSearchable.fromJson((item as Map).cast()),
        ],
      );

  final String originalQuery;
  final String version;
  final String? rewriteId;
  final String? translationEn;
  final List<Criterion> must;
  final List<Criterion> nice;
  final List<NotSearchable> notSearchable;

  bool get isEmpty => must.isEmpty && nice.isEmpty && notSearchable.isEmpty;
}
