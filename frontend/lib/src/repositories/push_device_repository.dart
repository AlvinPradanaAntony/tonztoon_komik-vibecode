import '../core/api_client.dart';

class PushDeviceRepository {
  PushDeviceRepository(this._api);

  final TonztoonApi _api;

  Future<void> registerFcmToken({
    required String token,
    required String userId,
  }) {
    return _api.post<void>(
      '/notifications/devices',
      data: {
        'provider': 'fcm',
        'platform': 'android',
        'token': token,
        'user_id': userId,
      },
    );
  }

  Future<void> unregisterFcmToken(String token) {
    return _api.delete<void>(
      '/notifications/devices',
      data: {'provider': 'fcm', 'platform': 'android', 'token': token},
    );
  }
}
