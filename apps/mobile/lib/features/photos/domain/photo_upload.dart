import 'package:meta/meta.dart';

/// A reserved slot from `POST /v1/photos/upload-urls` or its refresh.
///
/// [uploadToken] is a short-lived capability: kept in memory only, never
/// logged or written to the draft (BE doc §8.5).
@immutable
class UploadSlot {
  const UploadSlot({
    required this.photoId,
    required this.bucket,
    required this.path,
    required this.uploadToken,
    required this.expiresAt,
  });

  factory UploadSlot.fromJson(Map<String, Object?> j) => UploadSlot(
    photoId: j['photo_id']! as String,
    bucket: j['bucket']! as String,
    path: j['path']! as String,
    uploadToken: j['upload_token']! as String,
    expiresAt:
        DateTime.tryParse(j['expires_at'] as String? ?? '') ?? DateTime(0),
  );

  final String photoId;
  final String bucket;
  final String path;
  final String uploadToken;
  final DateTime expiresAt;

  /// Treats a token as expired a minute early to cover clock drift.
  bool isUsableAt(DateTime now) =>
      expiresAt.isAfter(now.add(const Duration(minutes: 1)));

  @override
  String toString() => 'UploadSlot($photoId)';
}

@immutable
class PhotoFileMeta {
  const PhotoFileMeta({
    required this.filename,
    required this.contentType,
    required this.fileSize,
  });

  final String filename;
  final String contentType;
  final int fileSize;

  Map<String, Object?> toJson() => {
    'filename': filename,
    'content_type': contentType,
    'file_size': fileSize,
  };
}

/// Go API side of photos (BE doc §8.5).
abstract interface class PhotoRepository {
  Future<List<UploadSlot>> reserve(List<PhotoFileMeta> files);
  Future<UploadSlot> refreshSlot(String photoId);
  Future<void> delete(String photoId);

  /// Short-lived signed read URLs by photo id, for tiles whose local file
  /// is already gone.
  Future<Map<String, String>> signedUrls();
}

/// Direct upload to Supabase Storage with a signed token.
abstract interface class PhotoStorage {
  Future<void> upload(UploadSlot slot, String filePath);
}

/// Device photo library.
abstract interface class PhotoPicker {
  /// Up to [max] photos; empty when the user cancels.
  Future<List<String>> pick({required int max});
}

/// Resizes to about 1080 px and re-encodes as JPEG, stripping EXIF (which
/// can hold GPS). Returns the new temp file path.
abstract interface class PhotoCompressor {
  Future<String> compress(String sourcePath);
}
