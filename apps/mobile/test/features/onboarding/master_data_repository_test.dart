import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oma_app/core/api/api_client.dart';
import 'package:oma_app/features/onboarding/data/api_master_data_repository.dart';
import 'package:oma_app/features/onboarding/domain/entities/master_option.dart';

import '../../helpers/fakes.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);

  final String body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('reads master data from the profile-data endpoint', () async {
    final adapter = _Adapter(
      '{"data":{"items":[{"id":"g1","label":"Woman"}],'
      '"pagination":{"page":2,"total_pages":3}}}',
    );
    final dio = buildApiDio(
      config: testConfig,
      tokens: FakeAuthRepository(testUser),
    )..httpClientAdapter = adapter;

    final page = await ApiMasterDataRepository(ApiClient(dio))
        .page(MasterDataType.gender, page: 2, limit: 20);

    final request = adapter.requests.single;
    expect(request.uri.path, '/v1/profile-data');
    expect(request.uri.queryParameters['type'], 'gender');
    expect(request.uri.queryParameters['page'], '2');
    expect(page.items.single.label, 'Woman');
    expect(page.page, 2);
    expect(page.totalPages, 3);
  });
}
