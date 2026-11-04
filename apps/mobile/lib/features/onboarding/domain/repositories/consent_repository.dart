import '../entities/consent_document.dart';

abstract interface class ConsentRepository {
  Future<List<ConsentDocument>> activeDocuments();

  /// `POST /v1/me/consents`. The backend resolves the versions.
  Future<void> accept(Iterable<String> types);
}
