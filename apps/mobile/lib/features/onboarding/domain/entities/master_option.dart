import 'package:meta/meta.dart';

enum MasterDataType {
  gender('gender'),
  pronoun('pronoun'),
  showMe('show_me'),
  lookingFor('looking_for'),
  university('university'),
  religion('religion'),
  personality('personality'),
  hobbyCategory('hobby_category'),
  hobby('hobby');

  const MasterDataType(this.wire);

  final String wire;
}

/// One option. Universities have `name` instead of `label`; both map here.
@immutable
class MasterOption {
  const MasterOption({
    required this.id,
    required this.label,
    this.code,
    this.categoryId,
  });

  factory MasterOption.fromJson(Map<String, Object?> j) => MasterOption(
    id: j['id']! as String,
    label: (j['label'] ?? j['name'] ?? '') as String,
    code: j['code'] as String?,
    categoryId: j['category_id'] as String?,
  );

  final String id;
  final String label;
  final String? code;

  final String? categoryId;

  @override
  bool operator ==(Object other) => other is MasterOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class MasterDataPage {
  const MasterDataPage({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  final List<MasterOption> items;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;
}
