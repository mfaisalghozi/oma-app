import '../entities/swipe_command.dart';

/// Decisions that could not reach the server yet. Survives a restart, so a
/// swipe made offline is not lost while the batch is still valid.
abstract interface class SwipeOutbox {
  Future<List<SwipeCommand>> load();

  Future<void> save(List<SwipeCommand> commands);
}
