import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/entities/deck_page.dart';
import '../domain/repositories/deck_repository.dart';

class ApiDeckRepository implements DeckRepository {
  ApiDeckRepository(this._client);

  final ApiClient _client;

  @override
  Future<DeckPage> fetch({int limit = 20, String? cursor}) async {
    final data = await _client.get(
      '/discovery',
      headers: {'X-Limit': '$limit', 'X-Cursor': ?cursor},
    );
    if (data is! Map) {
      throw const UnexpectedFailure('discovery: unexpected body');
    }
    return DeckPage.fromJson(data.cast());
  }
}
