import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/entities/swipe_command.dart';
import '../domain/repositories/swipe_outbox.dart';

/// Keeps pending decisions in the Keychain / Keystore so a swipe made offline
/// survives a restart. Only ids, kinds and timestamps are stored, never profile
/// data.
class SecureSwipeOutbox implements SwipeOutbox {
  SecureSwipeOutbox([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'oma.swipe.outbox';

  final FlutterSecureStorage _storage;

  @override
  Future<List<SwipeCommand>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded) SwipeCommand.fromJson((item as Map).cast()),
      ];
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> save(List<SwipeCommand> commands) async {
    if (commands.isEmpty) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(
      key: _key,
      value: jsonEncode([
        for (final command in commands) command.toStorageJson(),
      ]),
    );
  }
}
