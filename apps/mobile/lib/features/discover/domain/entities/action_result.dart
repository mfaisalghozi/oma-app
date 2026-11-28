import 'package:meta/meta.dart';

@immutable
class ActionResultMatch {
  const ActionResultMatch({
    required this.id,
    required this.conversationStatus,
    this.conversationId,
  });

  factory ActionResultMatch.fromJson(Map<String, Object?> json) =>
      ActionResultMatch(
        id: json['id'] as String? ?? '',
        conversationStatus: json['conversation_status'] as String? ?? 'pending',
        conversationId: json['conversation_id'] as String?,
      );

  final String id;
  final String conversationStatus;
  final String? conversationId;
}

/// The server's answer to one action. `match` is non-null only when the like
/// completed a mutual pair; the UI stays silent about it this sprint.
@immutable
class ActionResult {
  const ActionResult({
    required this.actionId,
    required this.action,
    this.match,
  });

  factory ActionResult.fromJson(Map<String, Object?> json) => ActionResult(
    actionId: json['action_id'] as String? ?? '',
    action: json['action'] as String? ?? '',
    match: json['match'] == null
        ? null
        : ActionResultMatch.fromJson((json['match'] as Map).cast()),
  );

  final String actionId;
  final String action;
  final ActionResultMatch? match;
}
