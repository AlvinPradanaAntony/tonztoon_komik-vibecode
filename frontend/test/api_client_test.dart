import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonztoon/src/core/api_client.dart';
import 'package:tonztoon/src/core/config.dart';
import 'package:tonztoon/src/core/token_store.dart';

void main() {
  test('api client uses a specific message for receive timeout', () async {
    final api = _apiRejectingWith(
      DioExceptionType.receiveTimeout,
      responseData: null,
    );

    await expectLater(
      api.get<Map<String, dynamic>>('/slow'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Server terlalu lama merespons. Silakan coba lagi beberapa saat lagi.',
        ),
      ),
    );
  });

  test('api client keeps connection errors distinct from timeout', () async {
    final api = _apiRejectingWith(
      DioExceptionType.connectionError,
      responseData: null,
    );

    await expectLater(
      api.get<Map<String, dynamic>>('/offline'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.',
        ),
      ),
    );
  });

  test('api client reads nested backend detail messages', () async {
    final api = _apiRejectingWith(
      DioExceptionType.badResponse,
      statusCode: 409,
      responseData: {
        'detail': {'message': 'Nama collection sudah digunakan.'},
      },
    );

    await expectLater(
      api.post<Map<String, dynamic>>('/library/collections'),
      throwsA(
        isA<ApiException>()
            .having(
              (error) => error.message,
              'message',
              'Nama collection sudah digunakan.',
            )
            .having((error) => error.statusCode, 'statusCode', 409),
      ),
    );
  });
}

TonztoonApi _apiRejectingWith(
  DioExceptionType type, {
  required Object? responseData,
  int? statusCode,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: type,
            response: statusCode == null
                ? null
                : Response<Object?>(
                    requestOptions: options,
                    statusCode: statusCode,
                    data: responseData,
                  ),
          ),
        );
      },
    ),
  );

  return TonztoonApi(
    config: const AppConfig(apiBaseUrl: 'https://api.test'),
    tokenStore: MemoryTokenStore(),
    dio: dio,
  );
}
