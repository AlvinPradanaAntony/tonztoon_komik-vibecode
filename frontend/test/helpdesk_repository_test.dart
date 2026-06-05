import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/core/api_client.dart';
import 'package:tonztoon/src/core/config.dart';
import 'package:tonztoon/src/core/token_store.dart';
import 'package:tonztoon/src/models/helpdesk.dart';
import 'package:tonztoon/src/repositories/helpdesk_repository.dart';

void main() {
  test('submits helpdesk report and parses receipt', () async {
    Object? sentData;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          sentData = options.data;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 201,
              data: {
                'id': 'submission-id',
                'reference_code': 'TT-A1B2C3D4',
                'category': 'report',
                'status': 'open',
                'created_at': '2026-06-05T10:00:00Z',
              },
            ),
          );
        },
      ),
    );
    final repository = HelpdeskRepository(
      TonztoonApi(
        config: const AppConfig(apiBaseUrl: 'https://api.test'),
        tokenStore: MemoryTokenStore(),
        dio: dio,
      ),
    );

    final receipt = await repository.submit(
      const HelpdeskSubmissionDraft(
        category: HelpdeskCategory.report,
        title: 'Chapter tidak terbuka',
        message: 'Layar terus memuat setelah chapter dipilih.',
      ),
    );

    expect(receipt.referenceCode, 'TT-A1B2C3D4');
    expect(receipt.category, HelpdeskCategory.report);
    expect(sentData, isA<Map<String, dynamic>>());
    final payload = sentData! as Map<String, dynamic>;
    expect(payload['category'], 'report');
    expect(payload['title'], 'Chapter tidak terbuka');
    expect(payload['rating'], isNull);
    expect(payload['client_context'], {'source': 'home_helpdesk'});
  });
}
