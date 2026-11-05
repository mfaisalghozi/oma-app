import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/api/api_client.dart';
import 'package:oma_app/core/errors/failure.dart';
import 'package:oma_app/features/auth/application/session_controller.dart';
import 'package:oma_app/features/auth/domain/entities/account_state.dart';
import 'package:oma_app/features/onboarding/application/consent_controller.dart';
import 'package:oma_app/features/onboarding/domain/entities/consent_document.dart';
import 'package:oma_app/features/onboarding/domain/repositories/consent_repository.dart';
import 'package:oma_app/features/onboarding/presentation/consent_screen.dart';

import '../../helpers/fakes.dart';
import '../../helpers/golden.dart';

const _docs = [
  ConsentDocument(
    type: 'terms',
    title: 'Terms of Use',
    version: '1.0',
    documentUrl: '/legal/terms/1.0',
    required: true,
  ),
  ConsentDocument(
    type: 'privacy',
    title: 'Privacy Policy',
    version: '1.0',
    documentUrl: 'https://oma.app/legal/privacy/1.0',
    required: true,
  ),
  ConsentDocument(
    type: 'sensitive_data',
    title: 'Sensitive profile data',
    version: '1.0',
    documentUrl: '',
    required: true,
  ),
];

class FakeConsentRepository implements ConsentRepository {
  List<ConsentDocument> docs = _docs;
  Object? acceptError;
  List<String>? accepted;

  @override
  Future<List<ConsentDocument>> activeDocuments() async => docs;

  @override
  Future<void> accept(Iterable<String> types) async {
    if (acceptError != null) throw acceptError!;
    accepted = types.toList();
  }
}

void main() {
  late FakeAuthRepository auth;
  late FakeAccountRepository accounts;
  late FakeConsentRepository consents;

  setUp(() {
    auth = FakeAuthRepository(testUser);
    accounts = FakeAccountRepository(account(next: NextAction.acceptConsents));
    consents = FakeConsentRepository();
  });

  List<Override> overrides() => [
    ...baseOverrides(auth: auth, accounts: accounts),
    consentRepositoryProvider.overrideWithValue(consents),
  ];

  ProviderContainer create() {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    c.listen(consentControllerProvider, (_, _) {});
    return c;
  }

  group('ConsentController', () {
    test('Continue needs every required tick', () async {
      final c = create();
      var s = await c.read(consentControllerProvider.future);
      expect(s.canContinue, isFalse);
      final n = c.read(consentControllerProvider.notifier);
      n.toggle('terms');
      n.toggle('privacy');
      expect(c.read(consentControllerProvider).value!.canContinue, isFalse);
      n.toggle('sensitive_data');
      s = c.read(consentControllerProvider).value!;
      expect(s.canContinue, isTrue);
      n.toggle('privacy');
      expect(c.read(consentControllerProvider).value!.canContinue, isFalse);
    });

    test('optional documents do not block Continue', () async {
      consents.docs = [
        _docs.first,
        const ConsentDocument(
          type: 'marketing',
          title: 'Tips by email',
          version: '1',
          documentUrl: '',
          required: false,
        ),
      ];
      final c = create();
      await c.read(consentControllerProvider.future);
      c.read(consentControllerProvider.notifier).toggle('terms');
      expect(c.read(consentControllerProvider).value!.canContinue, isTrue);
    });

    test('submit saves the ticks and refreshes the session', () async {
      final c = create();
      await c.read(sessionControllerProvider.future);
      await c.read(consentControllerProvider.future);
      final n = c.read(consentControllerProvider.notifier);
      for (final d in _docs) {
        n.toggle(d.type);
      }
      accounts.result = account();
      await n.submit();

      expect(consents.accepted, unorderedEquals(_docs.map((d) => d.type)));
      final session = c.read(sessionControllerProvider).value! as SignedIn;
      expect(session.account.nextAction, NextAction.completeOnboarding);
    });

    test('a network error keeps the ticks and shows the error', () async {
      consents.acceptError = const NetworkFailure();
      final c = create();
      await c.read(consentControllerProvider.future);
      final n = c.read(consentControllerProvider.notifier);
      for (final d in _docs) {
        n.toggle(d.type);
      }
      await n.submit();
      final s = c.read(consentControllerProvider).value!;
      expect(s.error, isA<NetworkFailure>());
      expect(s.ticked, hasLength(3));
      expect(s.saving, isFalse);
      expect(s.canContinue, isTrue);
    });
  });

  test('CONSENT_REQUIRED from any endpoint fires the handler', () async {
    var fired = 0;
    final dio = Dio()
      ..httpClientAdapter = _StaticAdapter(403, {
        'error': {'code': 'CONSENT_REQUIRED', 'message': 'x'},
      })
      ..interceptors.add(ConsentRequiredInterceptor(() async => fired++));
    await expectLater(
      ApiClient(dio).get('/discover'),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.code,
          'code',
          ApiErrorCode.consentRequired,
        ),
      ),
    );
    expect(fired, 1);
  });

  group('M05 screen', () {
    testWidgets('ticking all enables Agree and continue', (tester) async {
      await pumpScreen(tester, const ConsentScreen(), overrides: overrides());
      await tester.pumpAndSettle();
      expect(find.text('Check all to continue.'), findsOneWidget);
      for (final d in _docs) {
        await tester.tap(find.text(d.title).first);
        await tester.pump();
      }
      expect(find.text('Check all to continue.'), findsNothing);
    });

    goldenBothThemes('m05_consent', (tester, theme) async {
      await pumpScreen(
        tester,
        const ConsentScreen(),
        theme: theme,
        overrides: overrides(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terms of Use').first);
      await tester.pumpAndSettle();
    });

    goldenBothThemes('m05_consent_offline', (tester, theme) async {
      consents.acceptError = const NetworkFailure();
      await pumpScreen(
        tester,
        const ConsentScreen(),
        theme: theme,
        overrides: overrides(),
      );
      await tester.pumpAndSettle();
      for (final d in _docs) {
        await tester.tap(find.text(d.title).first);
        await tester.pump();
      }
      await tester.tap(find.text('Agree and continue'));
      await tester.pumpAndSettle();
    });
  });
}

class _StaticAdapter implements HttpClientAdapter {
  _StaticAdapter(this.status, this.body);

  final int status;
  final Map<String, Object?> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{"error":{"code":"${(body['error']! as Map)['code']}","message":"x"}}',
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
