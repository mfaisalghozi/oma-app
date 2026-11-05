import 'dart:io';

import 'package:nsfw_detect/nsfw_detect.dart';

import '../../../core/errors/failure.dart';
import '../domain/photo_scanner.dart';
import 'model_fetcher.dart';

abstract interface class NsfwEngine {
  Future<void> register({required String id, required String path});

  Future<NsfwScan> scanFile(String path, {required String modelId});
}

class NsfwScan {
  const NsfwScan({
    required this.completed,
    required this.category,
    required this.confidence,
  });

  final bool completed;
  final NsfwCategory category;
  final double confidence;
}

class NsfwDetectEngine implements NsfwEngine {
  @override
  Future<void> register({required String id, required String path}) async {
    await NsfwDetector.instance.registerModel(
      ModelRegistration(
        id: id,
        displayName: 'OMA photo check',
        assetPath: path,
        // OpenNSFW2 is a 2-class classifier.
        classLabels: const ['safe', 'nudity'],
      ),
    );
  }

  @override
  Future<NsfwScan> scanFile(String path, {required String modelId}) async {
    final r = await NsfwDetector.instance.scanFile(path, modelId: modelId);
    return NsfwScan(
      completed: r.status == ScanStatus.completed,
      category: r.topCategory,
      confidence: r.topConfidence,
    );
  }
}

/// Not the package's built-in models: they download with no checksum.
class NsfwDetectPhotoScanner implements PhotoScanner {
  NsfwDetectPhotoScanner({
    required this.fetcher,
    required this.threshold,
    NsfwEngine? engine,
  }) : _engine = engine ?? NsfwDetectEngine();

  static const modelId = 'oma_nsfw_v1';

  final ModelFetcher fetcher;
  final double threshold;
  final NsfwEngine _engine;
  Future<void>? _ready;

  @override
  Future<void> prepare() => _ready ??= _register().catchError((Object e) {
    _ready = null; // allow Try again
    throw e;
  });

  Future<void> _register() async {
    final File file = await fetcher.ensure();
    try {
      await _engine.register(id: modelId, path: file.path);
    } on Object {
      throw const DeviceFailure('nsfw model registration failed');
    }
  }

  @override
  Future<PhotoVerdict> scan(String filePath) async {
    await prepare();
    final NsfwScan r;
    try {
      r = await _engine.scanFile(filePath, modelId: modelId);
    } on Object {
      throw const DeviceFailure('nsfw scan failed');
    }
    // Fail closed: a scan that didn't complete never counts as safe.
    if (!r.completed) throw const DeviceFailure('nsfw scan incomplete');
    if (r.confidence < threshold) return const PhotoAllowed();
    return switch (r.category) {
      NsfwCategory.nudity => const PhotoRejected(PhotoRejectReason.nudity),
      NsfwCategory.explicitNudity => const PhotoRejected(
        PhotoRejectReason.explicitNudity,
      ),
      // Suggestive (swimwear, gym, freediving) is allowed on purpose.
      NsfwCategory.safe || NsfwCategory.suggestive => const PhotoAllowed(),
      // Unknown is not evidence of safety.
      NsfwCategory.unknown => throw const DeviceFailure('nsfw scan unknown'),
    };
  }
}
