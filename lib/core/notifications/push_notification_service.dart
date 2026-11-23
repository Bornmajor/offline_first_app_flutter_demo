import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Everything about push notifications (FCM) lives here.
///
/// Step 2 (now): connect to Firebase, ask for permission, print the token.
/// Later steps add: showing notifications, sending the token to our server,
/// and opening a subscription when a notification is tapped.
class PushNotificationService {
  /// FCM works on Android (and iOS with extra setup). On Windows, web and in
  /// tests every method simply does nothing.
  bool get _isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Called once when the app starts.
  Future<void> initialize() async {
    if (!_isSupported) return;

    try {
      // 1. Connect to Firebase. On Android the settings come from
      //    android/app/google-services.json (via the Google Services plugin).
      await Firebase.initializeApp();

      final messaging = FirebaseMessaging.instance;

      // 2. Ask permission to show notifications. Android 13+ shows a system
      //    dialog the first time; older Android versions allow it by default.
      //    If the user says no, notifications are silently dropped.
      final settings = await messaging.requestPermission();
      debugPrint(
        'Notification permission: ${settings.authorizationStatus.name}',
      );

      // 3. The token = this phone's "push address". Our server will send
      //    messages to it (Step 4 sends it to the server).
      //
      // Why the deprecated token API? firebase_messaging 17 introduced a
      // newer "direct send" model (register() + onRegistered, which give a
      // Firebase Installation ID). The classic registration token still
      // works, and it's what the Firebase console's "Send test message" and
      // firebase-admin's `token` target use — so every step of this tutorial
      // can be checked. Revisit once the FID route is supported end to end.
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      debugPrint('FCM token: $token');

      // 4. The token can change (reinstall, cleared data, Firebase rotating
      //    it). Step 4 will send the new one to the server.
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen(
        (newToken) => debugPrint('FCM token refreshed: $newToken'),
      );
    } catch (error) {
      // No Google Play services, no network for the first token, etc.
      // Push is optional: the app must keep working without it.
      debugPrint('Push notifications not available: $error');
    }
  }
}
