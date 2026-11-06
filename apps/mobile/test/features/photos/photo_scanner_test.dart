import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsfw_detect/nsfw_detect.dart' show NsfwCategory;
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/photos/data/model_fetcher.dart';
import 'package:oma_app/features/photos/data/nsfw_detect_photo_scanner.dart';
import 'package:oma_app/features/photos/domain/photo_scanner.dart';

final _model = Uint8List.fromList(List.generate(4096, (i) => i % 251));
final _sha = sha256.convert(_model).toString();

class _ModelServer implements HttpClientAdapter {
  int hits = 0;
  Uint8List body = _model;
  bool fail = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    hits++;
    if (fail) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromBytes(body, 200);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeEngine implements NsfwEngine {
  NsfwScan next = const NsfwScan(
    completed: true,
    category: NsfwCategory.safe,
    confidence: 0.99,
  );
  Object? scanError;
  int registers = 0;
  String? registeredPath;

  @override
  Future<void> register({required String id, required String path}) async {
    registers++;
    registeredPath = path;
  }

  @override
  Future<NsfwScan> scanFile(String path, {required String modelId}) async {
    if (scanError != null) throw scanError!;
    return next;
  }
}

void main() {
  late Directory dir;
  late _ModelServer server;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('oma_nsfw');
    server = _ModelServer();
  });
  tearDown(() => dir.delete(recursive: true));

  ModelFetcher fetcher({
    String? sha,
    String url = 'https://m.oma.app/m.tflite',
  }) => ModelFetcher(
    url: url,
    sha256Hex: sha ?? _sha,
    directory: () async => dir,
    dio: Dio()..httpClientAdapter = server,
  );

  group('ModelFetcher', () {
    test('downloads once, then reuses the verified file', () async {
      final f = fetcher();
      final a = await f.ensure();
      final b = await f.ensure();
      expect(a.path, b.path);
      expect(await a.readAsBytes(), _model);
      expect(server.hits, 1);
    });

    test('a checksum mismatch fails closed and leaves no file', () async {
      server.body = Uint8List.fromList([1, 2, 3]);
      await expectLater(fetcher().ensure(), throwsA(isA<DeviceFailure>()));
      expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('a tampered cached file is downloaded again', () async {
      final f = fetcher();
      final file = await f.ensure();
      await file.writeAsBytes([9, 9, 9]);
      await f.ensure();
      expect(server.hits, 2);
      expect(await file.readAsBytes(), _model);
    });

    test('offline download is a DeviceFailure', () async {
      server.fail = true;
      await expectLater(fetcher().ensure(), throwsA(isA<DeviceFailure>()));
    });

    test('refuses an unconfigured or non-https mirror', () async {
      await expectLater(
        fetcher(url: 'http://m.oma.app/m.tflite').ensure(),
        throwsA(isA<DeviceFailure>()),
      );
      await expectLater(
        fetcher(sha: '').ensure(),
        throwsA(isA<DeviceFailure>()),
      );
      expect(server.hits, 0);
    });
  });

  group('NsfwDetectPhotoScanner', () {
    late _FakeEngine engine;
    late NsfwDetectPhotoScanner scanner;

    setUp(() {
      engine = _FakeEngine();
      scanner = NsfwDetectPhotoScanner(
        fetcher: fetcher(),
        threshold: 0.7,
        engine: engine,
      );
    });

    NsfwScan scan(NsfwCategory c, double p, {bool completed = true}) =>
        NsfwScan(completed: completed, category: c, confidence: p);

    test('registers the verified model once per process', () async {
      await scanner.scan('/a.jpg');
      await scanner.scan('/b.jpg');
      expect(engine.registers, 1);
      expect(engine.registeredPath, endsWith('nsfw/m.tflite'));
    });

    test('nudity and explicit nudity at the threshold are rejected', () async {
      engine.next = scan(NsfwCategory.nudity, 0.7);
      expect(
        await scanner.scan('/a.jpg'),
        isA<PhotoRejected>().having(
          (r) => r.reason,
          'reason',
          PhotoRejectReason.nudity,
        ),
      );
      engine.next = scan(NsfwCategory.explicitNudity, 0.95);
      expect(
        await scanner.scan('/a.jpg'),
        isA<PhotoRejected>().having(
          (r) => r.reason,
          'reason',
          PhotoRejectReason.explicitNudity,
        ),
      );
    });

    test('below the threshold or suggestive is allowed', () async {
      engine.next = scan(NsfwCategory.nudity, 0.69);
      expect(await scanner.scan('/a.jpg'), isA<PhotoAllowed>());
      engine.next = scan(NsfwCategory.suggestive, 0.99);
      expect(await scanner.scan('/a.jpg'), isA<PhotoAllowed>());
    });

    test('fails closed on an engine error or incomplete scan', () async {
      engine.scanError = Exception('boom');
      await expectLater(scanner.scan('/a.jpg'), throwsA(isA<DeviceFailure>()));
      engine
        ..scanError = null
        ..next = scan(NsfwCategory.safe, 0.99, completed: false);
      await expectLater(scanner.scan('/a.jpg'), throwsA(isA<DeviceFailure>()));
      engine.next = scan(NsfwCategory.unknown, 0.99);
      await expectLater(scanner.scan('/a.jpg'), throwsA(isA<DeviceFailure>()));
      // Below the threshold is still a failure: unknown is not "safe enough".
      engine.next = scan(NsfwCategory.unknown, 0.5);
      await expectLater(scanner.scan('/a.jpg'), throwsA(isA<DeviceFailure>()));
    });

    test('a failed model download can be retried', () async {
      server.fail = true;
      await expectLater(scanner.prepare(), throwsA(isA<DeviceFailure>()));
      server.fail = false;
      await scanner.prepare();
      expect(engine.registers, 1);
    });
  });
}
