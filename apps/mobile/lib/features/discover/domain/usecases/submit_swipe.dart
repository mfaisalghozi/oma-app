import '../../../../core/errors/failure.dart';
import '../entities/swipe_command.dart';
import '../repositories/swipe_outbox.dart';
import '../repositories/swipe_repository.dart';

/// What the controller needs to know to update the deck.
enum SwipeOutcome {
  /// The server accepted the decision.
  accepted,

  /// No connection or a 5xx: the command waits in the outbox.
  queued,

  /// The daily like quota is gone. The card goes back on top.
  likeLimit,

  /// Super likes are not configured. The card goes back on top.
  superLikeEmpty,

  /// The batch expired or the preference changed. Drop the decision, reload.
  staleContext,

  /// The pair was already decided or the card is gone. Drop silently.
  dropped,

  /// The account cannot swipe any more. Re-run the gates.
  gate,
}

/// Sends one decision. Never throws for the cases the deck has a state for.
class SubmitSwipe {
  SubmitSwipe(this._repository, this._outbox);

  final SwipeRepository _repository;
  final SwipeOutbox _outbox;

  Future<SwipeOutcome> call(SwipeCommand command) async {
    try {
      await _repository.submit(command);
      return SwipeOutcome.accepted;
    } on NetworkFailure {
      await _queue(command);
      return SwipeOutcome.queued;
    } on ApiFailure catch (failure) {
      switch (failure.code) {
        case ApiErrorCode.likeLimitReached:
          return SwipeOutcome.likeLimit;
        case ApiErrorCode.superLikeBalanceEmpty:
          return SwipeOutcome.superLikeEmpty;
        case ApiErrorCode.staleDiscoveryContext:
        case ApiErrorCode.invalidCursor:
          return SwipeOutcome.staleContext;
        case ApiErrorCode.notFound:
        case ApiErrorCode.actionConflict:
        case ApiErrorCode.idempotencyConflict:
        case ApiErrorCode.invalidAction:
          return SwipeOutcome.dropped;
        case ApiErrorCode.accountSuspended:
        case ApiErrorCode.accountFrozen:
        case ApiErrorCode.discoveryNotEligible:
        case ApiErrorCode.onboardingRequired:
        case ApiErrorCode.locationRequired:
          return SwipeOutcome.gate;
        default:
          if ((failure.statusCode ?? 0) >= 500) {
            await _queue(command);
            return SwipeOutcome.queued;
          }
          return SwipeOutcome.dropped;
      }
    } on UnexpectedFailure {
      await _queue(command);
      return SwipeOutcome.queued;
    }
  }

  Future<void> _queue(SwipeCommand command) async {
    final pending = await _outbox.load();
    if (pending.any((item) => item.idempotencyKey == command.idempotencyKey)) {
      return;
    }
    await _outbox.save([...pending, command]);
  }
}
