import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Runs when a push arrives while the app is in the BACKGROUND or CLOSED.
///
/// Like the WorkManager task, Android starts a separate Dart isolate for it,
/// so nothing from the app (providers, database object…) exists here. It must
/// be a top-level function, and `@pragma('vm:entry-point')` keeps it in
/// release builds.
///
/// We don't show anything here: for messages with a `notification` part the
/// SYSTEM already shows it (on our channel). Step 3 only logs, to see the flow.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    'Push received in background: '
    '${message.notification?.title} · data: ${message.data}',
  );
}

/// Everything about push notifications (FCM) lives here.
///
/// Done so far:
///   Step 2 — connect to Firebase, ask for permission, get the token
///   Step 3 — our notification channel; show pushes while the app is open;
///            background handler
/// Later: send the token to our server (4), open a subscription on tap (7).
class PushNotificationService {
  /// Android notification channel for reminders. Each notification belongs to
  /// a channel; the user can mute or tune each channel in system settings.
  /// High importance = it pops up on screen (heads-up), with sound.
  ///
  /// The id must match the default channel in AndroidManifest.xml and the
  /// `channel_id` the server sends.
  static const reminderChannel = AndroidNotificationChannel(
    'subscription_reminders',
    'Subscription reminders',
    description: 'Alerts before a subscription renews',
    importance: Importance.high,
  );

  /// Shows notifications from our OWN code (needed while the app is open).
  final _localNotifications = FlutterLocalNotificationsPlugin();

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

      // 2. Register the handler for pushes arriving in the background or
      //    while the app is closed (see firebaseMessagingBackgroundHandler).
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 3. Prepare local notifications and create our channel. Creating a
      //    channel that already exists does nothing, so this is safe on every
      //    start. (Permission is asked once, by firebase_messaging below.)
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(reminderChannel);

      final messaging = FirebaseMessaging.instance;

      // 4. Ask permission to show notifications. Android 13+ shows a system
      //    dialog the first time; older Android versions allow it by default.
      //    If the user says no, notifications are silently dropped.
      //    (Later: move this to the Reminders setting, with a "soft ask".)
      final settings = await messaging.requestPermission();
      debugPrint(
        'Notification permission: ${settings.authorizationStatus.name}',
      );

      // 5. The token = this phone's "push address". Our server will send
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

      // 6. The token can change (reinstall, cleared data, Firebase rotating
      //    it). Step 4 will send the new one to the server.
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen(
        (newToken) => debugPrint('FCM token refreshed: $newToken'),
      );

      // 7. App OPEN (foreground): Android does NOT show push notifications
      //    by itself, so we show it ourselves on our channel.
      FirebaseMessaging.onMessage.listen(_showWhileAppIsOpen);
    } catch (error) {
      // No Google Play services, no network for the first token, etc.
      // Push is optional: the app must keep working without it.
      debugPrint('Push notifications not available: $error');
    }
  }

  /// Shows a push that arrived while the app is on screen.
  Future<void> _showWhileAppIsOpen(RemoteMessage message) async {
    debugPrint(
      'Push received in foreground: '
      '${message.notification?.title} · data: ${message.data}',
    );

    // Data-only messages have nothing to show.
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      // Any int; reusing an id replaces that notification instead of adding
      // another one.
      id: message.messageId.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          reminderChannel.id,
          reminderChannel.name,
          channelDescription: reminderChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // Carried to the tap handler in Step 7 to open that subscription.
      payload: message.data['subscriptionId'],
    );
  }
}
