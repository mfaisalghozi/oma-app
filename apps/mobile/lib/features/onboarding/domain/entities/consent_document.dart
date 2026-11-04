/// One agreement from `GET /v1/consents/documents` (BE doc §8.3).
///
/// The list is rendered as the API returns it, so adding or splitting an
/// agreement (the PRD's third "storage in Singapore" tick is still open)
/// needs no app release.
class ConsentDocument {
  const ConsentDocument({
    required this.type,
    required this.title,
    required this.version,
    required this.documentUrl,
    required this.required,
  });

  factory ConsentDocument.fromJson(Map<String, Object?> json) =>
      ConsentDocument(
        type: json['type']! as String,
        title: json['title'] as String? ?? '',
        version: json['version'] as String? ?? '',
        documentUrl: json['document_url'] as String? ?? '',
        required: json['required'] != false,
      );

  final String type;
  final String title;
  final String version;

  /// Absolute, or relative to the public web (`/legal/terms/1.0`).
  final String documentUrl;
  final bool required;
}
