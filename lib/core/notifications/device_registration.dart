import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:offline_first_subscription_app/core/database/settings_dao.dart';
import 'package:offline_first_subscription_app/core/notifications/device_api.dart';
import 'package:offline_first_subscription_app/core/notifications/reminder_timing.dart';

/// Keeps the server up to date with this phone's push token and reminder
/// setting — offline-first, like everything else in the app.
///
/// It remembers two things locally:
///   • what the phone WANTS the server to know  (current token + setting)
///   • what the server was LAST TOLD             (registered token + setting)
/// and only calls the server when they differ. So:
///   • same token, same setting   → no request
///   • new token / new setting    → one request
///   • offline when it changed    → stays different → sent on the next try
class DeviceRegistration {
  DeviceRegistration(this._settings, this._api, {String? platform})
    : _platform = platform ?? (Platform.isIOS ? 'ios' : 'android');

  final SettingsDao _settings;
  final DeviceApi _api;
  final String _platform;

  static const _tokenKey = 'push.token';
  static const _timingKey = 'settings.reminderTiming';
  static const _registeredTokenKey = 'push.registeredToken';
  static const _registeredTimingKey = 'push.registeredReminderTiming';

  /// The reminder setting (for the settings screen).
  Future<ReminderTiming> getReminderTiming() async =>
      ReminderTiming.fromApiValue(await _settings.read(_timingKey));

  /// Firebase gave us a token (at start, or a new one after a refresh).
  Future<void> setToken(String token) async {
    await _settings.write(_tokenKey, token);
    await registerIfNeeded();
  }

  /// The user picked a reminder setting.
  Future<void> setReminderTiming(ReminderTiming timing) async {
    await _settings.write(_timingKey, timing.apiValue);
    await registerIfNeeded();
  }

  /// Sends the token + setting to the server if it doesn't have them yet.
  /// Safe to call any time (app start, back online…).
  Future<void> registerIfNeeded() async {
    final token = await _settings.read(_tokenKey);
    if (token == null) return; // No token yet: nothing to register.

    final timing = await getReminderTiming();
    final alreadyRegistered =
        await _settings.read(_registeredTokenKey) == token &&
        await _settings.read(_registeredTimingKey) == timing.apiValue;
    if (alreadyRegistered) return;

    try {
      await _api.register(
        token: token,
        platform: _platform,
        reminderTiming: timing,
      );
      // Remember what the server now knows, so we don't send it again.
      await _settings.write(_registeredTokenKey, token);
      await _settings.write(_registeredTimingKey, timing.apiValue);
      debugPrint('Device registered with server (${timing.apiValue})');
    } on DioException catch (error) {
      // Offline or server down: nothing is lost. The values still differ,
      // so the next registerIfNeeded() sends them.
      debugPrint('Device registration postponed: ${error.message}');
    }
  }
}
