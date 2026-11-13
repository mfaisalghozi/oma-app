import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oma_app/core/api/api_client.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/core/theme/oma_theme.dart';
import 'package:oma_app/features/device/application/device_registrar.dart';
import 'package:oma_app/features/device/domain/device_repository.dart';
import 'package:oma_app/features/device/domain/location_service.dart';
import 'package:oma_app/features/device/domain/push_service.dart';
import 'package:oma_app/features/onboarding/domain/entities/onboarding_draft.dart';
import 'package:oma_app/features/onboarding/presentation/steps/location_screen.dart';
import 'package:oma_app/features/onboarding/presentation/steps/notifications_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

class FakeLocation implements LocationService {
  LocationAccess answer = LocationAccess.granted;
  RoundedFix fix = (latitude: -6.2614, longitude: 106.8105);
  bool failFix = false;
  int requests = 0;
  int settingsOpened = 0;

  /// Holds [currentFix] open so a test can observe the in-flight state.
  Completer<void>? hold;

  @override
  Future<LocationAccess> status() async => answer;

  @override
  Future<LocationAccess> request() async {
    requests++;
    return answer;
  }

  @override
  Future<RoundedFix> currentFix() async {
    if (hold != null) await hold!.future;
    if (failFix) throw const DeviceFailure('fix');
    return fix;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class FakePush implements PushService {
  bool allow = true;
  String? tokenValue = 'fid-1';
  int prompts = 0;

  @override
  Future<bool> requestPermission() async {
    prompts++;
    return allow;
  }

  @override
  Future<String?> token() async => tokenValue;
}

class MemoryFlag implements PendingFlag {
  bool value = false;

  @override
  Future<bool> get() async => value;

  @override
  Future<void> set(bool v) async => value = v;
}

class FakeApi implements ApiClient {
  final posts = <String, Object?>{};
  Object? failWith;

  @override
  Future<Object?> post(
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (failWith != null) throw failWith!;
    posts[path] = body;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OnboardingDraft _upToPhotos() => OnboardingDraft(
  userId: 'u1',
  fullName: 'Rania',
  birthdate: DateTime(1998, 4, 2),
  genderId: 'g',
  showMeOptionId: 's',
  bio: 'Hi',
  lookingForIds: const ['l'],
  heightCm: 165,
  weightKg: 55,
  hobbyIds: const ['h'],
  photos: const [
    DraftPhoto(
      localPath: '/x',
      photoId: 'p1',
      status: DraftPhotoStatus.uploaded,
    ),
  ],
);

void main() {
  late MemoryDraftStore store;
  late FakeLocation location;
  late FakePush push;
  late MemoryFlag flag;
  late FakeApi api;

  setUp(() {
    store = MemoryDraftStore(_upToPhotos());
    location = FakeLocation();
    push = FakePush();
    flag = MemoryFlag();
    api = FakeApi();
  });

  List<Override> overrides() => [
    ...baseOverrides(
      auth: FakeAuthRepository(testUser),
      accounts: FakeAccountRepository(account()),
      drafts: store,
    ),
    locationServiceProvider.overrideWithValue(location),
    pushServiceProvider.overrideWithValue(push),
    pushPendingFlagProvider.overrideWithValue(flag),
    devicePlatformProvider.overrideWithValue(DevicePlatform.android),
    apiClientProvider.overrideWithValue(api),
  ];

  Future<void> pumpRouted(
    WidgetTester tester,
    Widget screen, {
    GoldenTheme theme = GoldenTheme.lagoon,
  }) async {
    await loadAppFonts();
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/here',
      routes: [
        GoRoute(path: '/here', builder: (_, _) => screen),
        GoRoute(
          path: '/onboarding/:step',
          builder: (_, s) => Text('went:${s.pathParameters['step']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: theme == GoldenTheme.lagoon
              ? OmaTheme.lagoon()
              : OmaTheme.deepSea(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('M10 location', () {
    testWidgets('Allow saves a fix rounded on the device', (tester) async {
      await pumpRouted(tester, const LocationScreen());
      await tester.tap(find.text('Allow location'));
      await tester.pumpAndSettle();
      final loc = store.saved!.location!;
      expect(loc.latitude, -6.26);
      expect(loc.longitude, 106.81);
      expect(loc.source, LocationSource.gps);
      expect(find.text('went:notifications'), findsOneWidget);
    });

    testWidgets('shows progress while the fix is in flight', (tester) async {
      final hold = Completer<void>();
      location.hold = hold;
      await pumpRouted(tester, const LocationScreen());

      await tester.tap(find.text('Allow location'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Getting your location…'), findsOneWidget);

      hold.complete();
      await tester.pumpAndSettle();
      expect(store.saved!.location!.source, LocationSource.gps);
    });

    testWidgets('denied shows the city picker; a city is saved', (
      tester,
    ) async {
      location.answer = LocationAccess.denied;
      await pumpRouted(tester, const LocationScreen());
      await tester.tap(find.text('Allow location'));
      await tester.pumpAndSettle();
      expect(find.text('Location is off'), findsOneWidget);

      await tester.tap(find.text('Open phone settings'));
      expect(location.settingsOpened, 1);

      await tester.tap(find.text('Bandung'));
      await tester.pump();
      await tester.tap(find.text('Use Bandung'));
      await tester.pumpAndSettle();
      expect(store.saved!.location!.cityName, 'Bandung');
      expect(store.saved!.location!.source, LocationSource.city);
    });

    testWidgets('Not now skips the OS dialog', (tester) async {
      await pumpRouted(tester, const LocationScreen());
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(location.requests, 0);
      expect(find.text('Use Jakarta Selatan'), findsOneWidget);
    });

    testWidgets('a failed fix falls back to the city picker', (tester) async {
      location.failFix = true;
      await pumpRouted(tester, const LocationScreen());
      await tester.tap(find.text('Allow location'));
      await tester.pumpAndSettle();
      expect(
        find.text("We couldn't get your location. Pick your city instead."),
        findsOneWidget,
      );
      expect(store.saved!.location, isNull);
    });

    goldenBothThemes('m10_location', (tester, theme) async {
      await pumpRouted(tester, const LocationScreen(), theme: theme);
    });

    goldenBothThemes('m10_location_denied', (tester, theme) async {
      await pumpRouted(tester, const LocationScreen(), theme: theme);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    });
  });

  group('M11 notifications', () {
    setUp(() {
      store.saved = _upToPhotos().copyWith(
        location: const Nullable(
          DraftLocation(
            latitude: -6.26,
            longitude: 106.81,
            source: LocationSource.gps,
          ),
        ),
      );
    });

    testWidgets('Turn on asks the OS and registers the device', (tester) async {
      await pumpRouted(tester, const NotificationsScreen());
      await tester.tap(find.text('Turn on notifications'));
      await tester.pumpAndSettle();
      expect(push.prompts, 1);
      expect(api.posts['/devices'], {
        'token': 'fid-1',
        'platform': 'android',
        'provider': 'fcm',
      });
      expect(store.saved!.notificationsDecided, isTrue);
      expect(find.text('went:setup'), findsOneWidget);
    });

    testWidgets('Maybe later skips the OS dialog and continues', (
      tester,
    ) async {
      await pumpRouted(tester, const NotificationsScreen());
      await tester.tap(find.text('Maybe later'));
      await tester.pumpAndSettle();
      expect(push.prompts, 0);
      expect(api.posts, isEmpty);
      expect(store.saved!.notificationsDecided, isTrue);
      expect(find.text('went:setup'), findsOneWidget);
    });

    testWidgets('a failed registration never blocks; it is owed', (
      tester,
    ) async {
      api.failWith = const NetworkFailure();
      await pumpRouted(tester, const NotificationsScreen());
      await tester.tap(find.text('Turn on notifications'));
      await tester.pumpAndSettle();
      expect(find.text('went:setup'), findsOneWidget);
      expect(flag.value, isTrue);
    });

    goldenBothThemes('m11_notifications', (tester, theme) async {
      await pumpRouted(tester, const NotificationsScreen(), theme: theme);
    });
  });

  group('DeviceRegistrar.retryPending', () {
    test('retries only when owed, then clears the flag', () async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      await c.read(deviceRegistrarProvider).retryPending();
      expect(api.posts, isEmpty);

      flag.value = true;
      await c.read(deviceRegistrarProvider).retryPending();
      expect(api.posts.keys, ['/devices']);
      expect(flag.value, isFalse);
    });

    test('no token on this build keeps it owed', () async {
      push.tokenValue = null;
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      await c.read(deviceRegistrarProvider).register();
      expect(api.posts, isEmpty);
      expect(flag.value, isTrue);
    });
  });
}
