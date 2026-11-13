import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';
import '../data/bypass_photo_scanner.dart';
import '../data/model_fetcher.dart';
import '../data/nsfw_detect_photo_scanner.dart';
import '../domain/photo_scanner.dart';

final photoScannerProvider = Provider<PhotoScanner>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.nsfwScanBypass) return const BypassPhotoScanner();
  final source = config.nsfwModel;
  final ios = Platform.isIOS;
  return NsfwDetectPhotoScanner(
    threshold: source.thresholdValue,
    fetcher: ModelFetcher(
      url: ios ? source.iosUrl : source.androidUrl,
      sha256Hex: ios ? source.iosSha256 : source.androidSha256,
      directory: getApplicationSupportDirectory,
    ),
  );
});
