import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/entities/action_result.dart';
import '../domain/entities/swipe_command.dart';
import '../domain/repositories/swipe_repository.dart';

class ApiSwipeRepository implements SwipeRepository {
  ApiSwipeRepository(this._client);

  final ApiClient _client;

  @override
  Future<ActionResult> submit(SwipeCommand command) async {
    final data = await _client.post(
      '/discovery/actions',
      body: command.toJson(),
      idempotencyKey: command.idempotencyKey,
    );
    if (data is! Map) {
      throw const UnexpectedFailure('discovery/actions: unexpected body');
    }
    return ActionResult.fromJson(data.cast());
  }
}
