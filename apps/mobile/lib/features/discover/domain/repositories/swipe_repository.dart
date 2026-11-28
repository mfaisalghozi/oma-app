import '../entities/action_result.dart';
import '../entities/swipe_command.dart';

abstract interface class SwipeRepository {
  Future<ActionResult> submit(SwipeCommand command);
}
