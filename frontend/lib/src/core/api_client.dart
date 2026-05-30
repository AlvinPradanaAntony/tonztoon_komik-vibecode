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
  static const Duration connectionTimeout = Duration(seconds: 15);
  static const Duration sendTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration tokenRefreshLeeway = Duration(minutes: 2);

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
               connectTimeout: connectionTimeout,
               sendTimeout: sendTimeout,
               receiveTimeout: receiveTimeout,
               headers: {'Accept': 'application/json'},
             ),
           ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final TokenStore _tokenStore;
  final Dio dio;
  Future<String?>? _refreshFuture;

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    var token = await _tokenStore.readAccessToken();
    final refreshToken = await _tokenStore.readRefreshToken();
    final expiresAt = await _tokenStore.readExpiresAt();

    if (refreshToken != null &&
        refreshToken.isNotEmpty &&
        _canRefreshForPath(options.path) &&
        _shouldRefresh(expiresAt)) {
      try {
        token = await _refreshAccessToken(refreshToken) ?? token;
      } on DioException catch (error) {
        if (_isInvalidRefresh(error)) {
          await _tokenStore.clear();
          token = null;
        }
      }
    }

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
        refreshToken.isEmpty ||
        !_canRefreshForPath(path)) {
      handler.next(error);
      return;
    }

    try {
      final accessToken = await _refreshAccessToken(refreshToken);
      if (accessToken == null) {
        await _tokenStore.clear();
        handler.next(error);
        return;
      }

      final retryOptions = error.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $accessToken';
      final response = await dio.fetch<dynamic>(retryOptions);
      handler.resolve(response);
    } on DioException catch (refreshError) {
      if (_isInvalidRefresh(refreshError)) {
        await _tokenStore.clear();
      }
      handler.next(error);
    } catch (_) {
      handler.next(error);
    }
  }

  bool _canRefreshForPath(String path) {
    return !path.contains('/auth/refresh') && !path.contains('/auth/login');
  }

  bool _shouldRefresh(int? expiresAt) {
    if (expiresAt == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return expiresAt - now <= tokenRefreshLeeway.inSeconds;
  }

  bool _isInvalidRefresh(DioException error) {
    return switch (error.response?.statusCode) {
      400 || 401 || 403 => true,
      _ => false,
    };
  }

  Future<String?> _refreshAccessToken(String refreshToken) {
    final currentRefresh = _refreshFuture;
    if (currentRefresh != null) return currentRefresh;

    final refresh = _performRefresh(refreshToken);
    _refreshFuture = refresh.whenComplete(() => _refreshFuture = null);
    return _refreshFuture!;
  }

  Future<String?> _performRefresh(String refreshToken) async {
    final refreshDio = Dio(
      BaseOptions(
        baseUrl: dio.options.baseUrl,
        connectTimeout: connectionTimeout,
        sendTimeout: sendTimeout,
        receiveTimeout: receiveTimeout,
        headers: {'Accept': 'application/json'},
      ),
    );
    final refreshResponse = await refreshDio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    final session = refreshResponse.data?['session'] as Map<String, dynamic>?;
    final accessToken = session?['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) return null;

    await _tokenStore.save(
      TokenPair(
        accessToken: accessToken,
        refreshToken: session?['refresh_token'] as String?,
        expiresAt: session?['expires_at'] as int?,
      ),
    );
    return accessToken;
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

  Future<Response<T>> patch<T>(String path, {Object? data}) {
    return _guard(() => dio.patch<T>(path, data: data));
  }

  Future<Response<T>> delete<T>(String path, {Object? data}) {
    return _guard(() => dio.delete<T>(path, data: data));
  }

  Future<Response<T>> _guard<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      final message = _messageForDioException(error);
      throw ApiException(message, statusCode: error.response?.statusCode);
    }
  }

  String _messageForDioException(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout =>
        'Waktu koneksi ke server habis. Periksa koneksi Anda lalu coba lagi.',
      DioExceptionType.sendTimeout =>
        'Pengiriman data terlalu lama. Silakan coba lagi.',
      DioExceptionType.receiveTimeout =>
        'Server terlalu lama merespons. Silakan coba lagi beberapa saat lagi.',
      DioExceptionType.connectionError =>
        'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.',
      _ => _messageFromResponse(error.response?.data),
    };
  }

  String _messageFromResponse(Object? data) {
    const fallback = 'Request failed. Please try again.';

    if (data is Map<String, dynamic>) {
      final message = _stringMessage(data['message']);
      if (message != null) return message;

      final detail = data['detail'];
      final detailMessage = _stringMessage(detail);
      if (detailMessage != null) return detailMessage;

      if (detail is Map<String, dynamic>) {
        return _messageFromResponse(detail);
      }
    }

    final message = _stringMessage(data);
    return message ?? fallback;
  }

  String? _stringMessage(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
