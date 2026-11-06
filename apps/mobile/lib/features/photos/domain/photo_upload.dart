import 'package:meta/meta.dart';

/// [uploadToken] lives in memory only; never logged or saved.
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

abstract interface class PhotoRepository {
  Future<List<UploadSlot>> reserve(List<PhotoFileMeta> files);
  Future<UploadSlot> refreshSlot(String photoId);
  Future<void> delete(String photoId);

  Future<Map<String, String>> signedUrls();
}

abstract interface class PhotoStorage {
  Future<void> upload(UploadSlot slot, String filePath);
}

abstract interface class PhotoPicker {
  Future<List<String>> pick({required int max});
}

/// Re-encodes as JPEG to strip EXIF, which can hold GPS.
abstract interface class PhotoCompressor {
  Future<String> compress(String sourcePath);
}
