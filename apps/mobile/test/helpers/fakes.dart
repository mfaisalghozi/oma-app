import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:oma_app/core/api/api_client.dart';
import 'package:oma_app/core/config/app_config.dart';
import 'package:oma_app/features/auth/application/auth_providers.dart';
import 'package:oma_app/features/auth/domain/entities/account_state.dart';
import 'package:oma_app/features/auth/domain/entities/auth_session.dart';
import 'package:oma_app/features/auth/domain/repositories/account_repository.dart';
import 'package:oma_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:oma_app/features/auth/domain/repositories/social_auth_repository.dart';
import 'package:oma_app/features/onboarding/application/onboarding_draft_controller.dart';
import 'package:oma_app/features/onboarding/domain/entities/onboarding_draft.dart';
import 'package:oma_app/features/onboarding/domain/repositories/onboarding_draft_store.dart';
import 'package:oma_app/features/photos/domain/photo_upload.dart';

const testConfig = AppConfig(
  flavor: 'test',
  supabaseUrl: 'https://test.supabase.co',
  supabasePublishableKey: 'test',
  apiBaseUrl: 'http://localhost:8080',
  authRedirectUrl: 'com.mfaisalghozi.omaapp://auth/callback',
);

const testUser = AuthSession(userId: 'u1', email: 'rania@example.com');

AccountState account({
  NextAction next = NextAction.completeOnboarding,
  AccountStatus status = AccountStatus.active,
}) => AccountState(
  userId: 'u1',
  status: status,
  onboardingCompleted: next == NextAction.discovery,
  nextAction: next,
);

class FakeAuthRepository implements AuthRepository, AccessTokenSource {
  FakeAuthRepository([this._session]);

  AuthSession? _session;
  final _changes = StreamController<AuthSession?>.broadcast();
  int signOutCalls = 0;

  void emit(AuthSession? session) {
    _session = session;
    _changes.add(session);
  }

  @override
  AuthSession? get currentSession => _session;

  @override
  Stream<AuthSession?> sessionChanges() => _changes.stream;

  @override
  Future<String?> accessToken() async => _session == null ? null : 'token';

  @override
  Future<bool> refreshSession() async => _session != null;

  @override
  Future<bool> refresh() => refreshSession();

  @override
  Future<void> onUnauthorized() => signOut();

  @override
  Future<void> signOut() async {
    signOutCalls++;
    emit(null);
  }
}

class FakeSocialAuthRepository implements SocialAuthRepository {
  @override
  bool get appleAvailable => false;

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signInWithApple() async {}
}

class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository(this.result);

  Object result;
  int calls = 0;

  @override
  Future<AccountState> initialize() async {
    calls++;
    final r = result;
    if (r is AccountState) return r;
    throw r;
  }
}

class MemoryDraftStore implements OnboardingDraftStore {
  MemoryDraftStore([this.saved]);

  OnboardingDraft? saved;
  int saves = 0;
  int clears = 0;

  @override
  Future<OnboardingDraft?> load() async => saved;

  @override
  Future<void> save(OnboardingDraft draft) async {
    saves++;
    saved = draft;
  }

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

class NoopPhotoRepository implements PhotoRepository {
  @override
  Future<List<UploadSlot>> reserve(List<PhotoFileMeta> files) async => const [];

  @override
  Future<UploadSlot> refreshSlot(String photoId) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(String photoId) async {}

  @override
  Future<Map<String, String>> signedUrls() async => const {};
}

List<Override> baseOverrides({
  required FakeAuthRepository auth,
  required FakeAccountRepository accounts,
  OnboardingDraftStore? drafts,
}) => [
  onboardingDraftStoreProvider.overrideWithValue(drafts ?? MemoryDraftStore()),
  appConfigProvider.overrideWithValue(testConfig),
  authRepositoryProvider.overrideWithValue(auth),
  accessTokenSourceProvider.overrideWithValue(auth),
  accountRepositoryProvider.overrideWithValue(accounts),
  socialAuthRepositoryProvider.overrideWithValue(FakeSocialAuthRepository()),
];
