import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/entities/onboarding_draft.dart';
import '../domain/repositories/onboarding_draft_store.dart';

class SecureOnboardingDraftStore implements OnboardingDraftStore {
  SecureOnboardingDraftStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const key = 'oma.onboarding.draft';
  final FlutterSecureStorage _storage;

  @override
  Future<OnboardingDraft?> load() async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is Map) return OnboardingDraft.fromJson(json.cast());
    } on Object {
      // A corrupt or older-format draft is dropped: the user re-answers
      // rather than the app crashing on start.
    }
    await clear();
    return null;
  }

  @override
  Future<void> save(OnboardingDraft draft) =>
      _storage.write(key: key, value: jsonEncode(draft.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: key);
}
