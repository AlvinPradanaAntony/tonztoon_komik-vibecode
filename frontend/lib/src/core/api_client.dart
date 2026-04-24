import 'package:dio/dio.dart';

import 'config.dart';
import 'token_store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class TonztoonApi {
  TonztoonApi({
    required AppConfig config,
    required TokenStore tokenStore,
    Dio? dio,
  }) : _tokenStore = tokenStore,
       dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: config.apiBaseUrl,
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
               headers: {'Accept': 'application/json'},
             ),
           ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final TokenStore _tokenStore;
  final Dio dio;
  bool _refreshing = false;

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStore.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final status = error.response?.statusCode;
    final path = error.requestOptions.path;
    final refreshToken = await _tokenStore.readRefreshToken();

    if (status != 401 ||
        refreshToken == null ||
        _refreshing ||
        path.contains('/auth/refresh') ||
        path.contains('/auth/login')) {
      handler.next(error);
      return;
    }

    try {
      _refreshing = true;
      final refreshDio = Dio(BaseOptions(baseUrl: dio.options.baseUrl));
      final refreshResponse = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final session = refreshResponse.data?['session'] as Map<String, dynamic>?;
      final accessToken = session?['access_token'] as String?;
      if (accessToken == null) {
        await _tokenStore.clear();
        handler.next(error);
        return;
      }
      await _tokenStore.save(
        TokenPair(
          accessToken: accessToken,
          refreshToken: session?['refresh_token'] as String?,
          expiresAt: session?['expires_at'] as int?,
        ),
      );

      final retryOptions = error.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $accessToken';
      final response = await dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } catch (_) {
      await _tokenStore.clear();
      handler.next(error);
    } finally {
      _refreshing = false;
    }
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _guard(() => dio.get<T>(path, queryParameters: queryParameters));
  }

  Future<Response<T>> post<T>(String path, {Object? data}) {
    return _guard(() => dio.post<T>(path, data: data));
  }

  Future<Response<T>> put<T>(String path, {Object? data}) {
    return _guard(() => dio.put<T>(path, data: data));
  }

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      final data = error.response?.data;
      String message = 'Request failed. Please try again.';
      if (data is Map<String, dynamic>) {
        message = (data['message'] ?? data['detail'] ?? message).toString();
      } else if (data is String && data.isNotEmpty) {
        message = data;
      }
      throw ApiException(message, statusCode: error.response?.statusCode);
    }
  }
}
