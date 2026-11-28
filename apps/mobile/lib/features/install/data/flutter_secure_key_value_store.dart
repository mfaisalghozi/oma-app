import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/first_launch_guard.dart';

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
