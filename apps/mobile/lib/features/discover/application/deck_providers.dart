import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/api_deck_repository.dart';
import '../data/api_swipe_repository.dart';
import '../data/secure_swipe_outbox.dart';
import '../domain/repositories/deck_repository.dart';
import '../domain/repositories/swipe_outbox.dart';
import '../domain/repositories/swipe_repository.dart';
import '../domain/usecases/submit_swipe.dart';

final deckRepositoryProvider = Provider<DeckRepository>(
  (ref) => ApiDeckRepository(ref.watch(apiClientProvider)),
);

final swipeRepositoryProvider = Provider<SwipeRepository>(
  (ref) => ApiSwipeRepository(ref.watch(apiClientProvider)),
);

final swipeOutboxProvider = Provider<SwipeOutbox>((ref) => SecureSwipeOutbox());

final submitSwipeProvider = Provider<SubmitSwipe>(
  (ref) => SubmitSwipe(
    ref.watch(swipeRepositoryProvider),
    ref.watch(swipeOutboxProvider),
  ),
);
