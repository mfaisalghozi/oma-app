import '../entities/consent_document.dart';

abstract interface class ConsentRepository {
  Future<List<ConsentDocument>> activeDocuments();

  Future<void> accept(Iterable<String> types);
}
