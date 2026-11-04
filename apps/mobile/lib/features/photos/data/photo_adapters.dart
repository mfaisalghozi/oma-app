import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/errors/failure.dart';
import '../domain/photo_upload.dart';

class ApiPhotoRepository implements PhotoRepository {
  ApiPhotoRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<UploadSlot>> reserve(List<PhotoFileMeta> files) async {
    final data = await _api.post(
      '/photos/upload-urls',
      body: {
        'photos': [for (final f in files) f.toJson()],
      },
    );
    if (data is! List) throw const UnexpectedFailure('upload-urls body');
    return [
      for (final s in data)
        if (s is Map) UploadSlot.fromJson(s.cast()),
    ];
  }

  @override
  Future<UploadSlot> refreshSlot(String photoId) async {
    final data = await _api.post('/photos/$photoId/upload-url');
    if (data is! Map) throw const UnexpectedFailure('upload-url body');
    return UploadSlot.fromJson(data.cast());
  }

  @override
  Future<void> delete(String photoId) => _api.delete('/photos/$photoId');

  @override
  Future<Map<String, String>> signedUrls() async {
    final data = await _api.get('/photos');
    if (data is! List) return const {};
    return {
      for (final p in data)
        if (p is Map && p['signed_url'] is String)
          p['id'] as String: p['signed_url'] as String,
    };
  }
}

class SupabasePhotoStorage implements PhotoStorage {
  @override
  Future<void> upload(UploadSlot slot, String filePath) async {
    try {
      await Supabase.instance.client.storage
          .from(slot.bucket)
          .uploadToSignedUrl(
            slot.path,
            slot.uploadToken,
            File(filePath),
            const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
    } on StorageException catch (e) {
      // 400/403: token expired or invalid; the caller refreshes and retries.
      throw ApiFailure(
        code: 'STORAGE_UPLOAD_FAILED',
        statusCode: int.tryParse(e.statusCode ?? ''),
        message: e.message,
      );
    } on SocketException {
      throw const NetworkFailure();
    }
  }
}

class ImagePickerPhotoPicker implements PhotoPicker {
  final _picker = ImagePicker();

  @override
  Future<List<String>> pick({required int max}) async {
    if (max <= 0) return const [];
    final files = max == 1
        ? [?await _picker.pickImage(source: ImageSource.gallery)]
        : await _picker.pickMultiImage(limit: max);
    return [for (final f in files.take(max)) f.path];
  }
}

class NativePhotoCompressor implements PhotoCompressor {
  static const _edge = 1080;

  @override
  Future<String> compress(String sourcePath) async {
    final dir = await getTemporaryDirectory();
    final target = '${dir.path}/oma_photo_${const Uuid().v4()}.jpg';
    final out = await FlutterImageCompress.compressAndGetFile(
      sourcePath,
      target,
      minWidth: _edge,
      minHeight: _edge,
      quality: 85,
    );
    if (out == null) throw const DeviceFailure('photo compression failed');
    return out.path;
  }
}
