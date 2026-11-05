import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/entities/consent_document.dart';
import '../domain/repositories/consent_repository.dart';

class ApiConsentRepository implements ConsentRepository {
  ApiConsentRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ConsentDocument>> activeDocuments() async {
    final data = await _api.get('/consents/documents');
    if (data is! List) {
      throw const UnexpectedFailure('consents/documents: unexpected body');
    }
    return [
      for (final d in data)
        if (d is Map) ConsentDocument.fromJson(d.cast<String, Object?>()),
    ];
  }

  @override
  Future<void> accept(Iterable<String> types) => _api.post(
    '/me/consents',
    body: {
      'consents': [
        for (final t in types) {'type': t, 'accepted': true},
      ],
    },
  );
}
