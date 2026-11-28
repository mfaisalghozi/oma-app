import 'package:meta/meta.dart';

import 'swipe_kind.dart';

/// A decision waiting for the server. The idempotency key is minted once and
/// reused on every retry, so a lost response never charges twice.
@immutable
class SwipeCommand {
  const SwipeCommand({
    required this.candidateId,
    required this.kind,
    required this.contextKind,
    required this.contextId,
    required this.idempotencyKey,
    required this.createdAt,
  });

  factory SwipeCommand.fromJson(Map<String, Object?> json) => SwipeCommand(
    candidateId: json['candidate_id'] as String? ?? '',
    kind: SwipeKind.values.firstWhere(
      (kind) => kind.wire == json['kind'],
      orElse: () => SwipeKind.pass,
    ),
    contextKind: json['context_kind'] as String? ?? 'regular_deck',
    contextId: json['context_id'] as String? ?? '',
    idempotencyKey: json['idempotency_key'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at']! as String),
  );

  final String candidateId;
  final SwipeKind kind;
  final String contextKind;
  final String contextId;
  final String idempotencyKey;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'candidate_id': candidateId,
    'kind': kind.wire,
    'context': {'kind': contextKind, 'id': contextId},
  };

  Map<String, Object?> toStorageJson() => {
    'candidate_id': candidateId,
    'kind': kind.wire,
    'context_kind': contextKind,
    'context_id': contextId,
    'idempotency_key': idempotencyKey,
    'created_at': createdAt.toIso8601String(),
  };
}
