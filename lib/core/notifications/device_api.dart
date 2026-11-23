import 'package:dio/dio.dart';
import 'package:offline_first_subscription_app/core/notifications/reminder_timing.dart';

/// Tells our server about this phone, so it can send push notifications.
///
///   POST /api/devices { token, platform, reminderTiming }
///
/// The server creates the device the first time and updates it afterwards
/// (same token → same device), so calling this again is always safe.
class DeviceApi {
  DeviceApi(this._dio);

  /// The shared client from core/network/dio_client.dart (address, API key).
  final Dio _dio;

  Future<void> register({
    required String token,
    required String platform,
    required ReminderTiming reminderTiming,
  }) async {
    await _dio.post<void>(
      '/api/devices',
      data: {
        'token': token,
        'platform': platform,
        'reminderTiming': reminderTiming.apiValue,
      },
    );
  }
}
