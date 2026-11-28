import '../entities/deck_page.dart';

abstract interface class DeckRepository {
  /// Reads one batch. The limit and cursor travel as headers (`X-Limit`,
  /// `X-Cursor`), never as query parameters.
  Future<DeckPage> fetch({int limit = 20, String? cursor});
}
