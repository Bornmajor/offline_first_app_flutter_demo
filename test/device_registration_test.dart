import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_subscription_app/core/database/app_database.dart';
import 'package:offline_first_subscription_app/core/notifications/device_api.dart';
import 'package:offline_first_subscription_app/core/notifications/device_registration.dart';
import 'package:offline_first_subscription_app/core/notifications/reminder_timing.dart';

import 'helpers/test_database.dart';

/// Records registrations instead of calling the server.
class _FakeDeviceApi implements DeviceApi {
  final calls = <String>[]; // "token|timing"
  bool offline = false;

  @override
  Future<void> register({
    required String token,
    required String platform,
    required ReminderTiming reminderTiming,
  }) async {
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      );
    }
    calls.add('$token|${reminderTiming.apiValue}');
  }
}

void main() {
  late AppDatabase db;
  late _FakeDeviceApi api;
  late DeviceRegistration registration;

  setUp(() {
    db = createTestDatabase();
    api = _FakeDeviceApi();
    registration = DeviceRegistration(db.settingsDao, api, platform: 'android');
  });
  tearDown(() => db.close());

  test('no token yet → nothing is sent', () async {
    await registration.setReminderTiming(ReminderTiming.onDueDate);

    expect(api.calls, isEmpty);
  });

  test('first token → registered with the default setting', () async {
    await registration.setToken('token-1');

    expect(api.calls, ['token-1|one_day_before']);
  });

  test('same token again (every app start) → no extra request', () async {
    await registration.setToken('token-1');
    await registration.setToken('token-1');
    await registration.registerIfNeeded();

    expect(api.calls, hasLength(1));
  });

  test('new token (refresh) → sent again', () async {
    await registration.setToken('token-1');
    await registration.setToken('token-2');

    expect(api.calls.last, 'token-2|one_day_before');
  });

  test('setting changed → sent with the new setting, and remembered', () async {
    await registration.setToken('token-1');
    await registration.setReminderTiming(ReminderTiming.onDueDate);

    expect(api.calls.last, 'token-1|on_due_date');
    expect(await registration.getReminderTiming(), ReminderTiming.onDueDate);
  });

  test('offline → nothing lost; sent on the next try', () async {
    api.offline = true;
    await registration.setToken('token-1');
    expect(api.calls, isEmpty);

    api.offline = false;
    await registration.registerIfNeeded(); // e.g. connection is back

    expect(api.calls, ['token-1|one_day_before']);
  });
}
