import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../core/errors/failure.dart';

/// SHA-256 is checked after download and before first use.
class ModelFetcher {
  ModelFetcher({
    required this.url,
    required this.sha256Hex,
    required this.directory,
    Dio? dio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 60),
             ),
           );

  final String url;
  final String sha256Hex;

  final Future<Directory> Function() directory;
  final Dio _dio;

  Future<File>? _inFlight;

  Future<File> ensure() =>
      _inFlight ??= _ensure().whenComplete(() => _inFlight = null);

  Future<File> _ensure() async {
    if (url.isEmpty || sha256Hex.isEmpty) {
      throw const DeviceFailure('nsfw model mirror is not configured');
    }
    if (!Uri.parse(url).isScheme('https')) {
      throw const DeviceFailure('nsfw model must come over https');
    }
    final dir = await directory();
    final name = Uri.parse(url).pathSegments.last;
    final file = File('${dir.path}/nsfw/$name');
    if (await file.exists() && await _matches(file)) return file;

    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.part');
    try {
      await _dio.download(url, tmp.path);
    } on DioException {
      if (await tmp.exists()) await tmp.delete();
      throw const DeviceFailure('nsfw model download failed');
    }
    if (!await _matches(tmp)) {
      await tmp.delete();
      throw const DeviceFailure('nsfw model sha256 mismatch');
    }
    return tmp.rename(file.path);
  }

  Future<bool> _matches(File f) async {
    final digest = await sha256.bind(f.openRead()).first;
    return digest.toString() == sha256Hex.toLowerCase();
  }
}
