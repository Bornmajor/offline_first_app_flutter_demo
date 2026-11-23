# Push Notifications — How FCM Works

Goal for this app: **the server notices a subscription is about to end and
sends a push notification; the phone receives it in every app state; tapping
it opens that subscription.**

This page explains the concepts first. Implementation steps follow as they're
built.

- [The big picture](#the-big-picture)
- [The delivery path ("what channel does it use?")](#the-delivery-path-what-channel-does-it-use)
- [Tokens — the phone's push address](#tokens--the-phones-push-address)
- [Message types](#message-types)
- [What happens in each app state](#what-happens-in-each-app-state)
- [Android notification channels](#android-notification-channels)
- [Permission](#permission)
- [Delivery options: priority, time-to-live, collapse key](#delivery-options-priority-time-to-live-collapse-key)
- [Our reminder message](#our-reminder-message)
- [The plan for this app](#the-plan-for-this-app)
- [Step 2 — Firebase setup, permission, token](#step-2--firebase-setup-permission-token)
- [Step 3 — Receive in every app state](#step-3--receive-in-every-app-state)

---

## The big picture

Three parties are involved:

| Party | Role in this app |
| --- | --- |
| **App server** | Our Express API. Decides *when* and *what* to send ("Netflix renews tomorrow"). |
| **FCM** (Firebase Cloud Messaging, run by Google) | The post office: accepts the message, keeps it while the phone is offline, delivers it. |
| **The app on the phone** | Registers for pushes, receives messages, shows the notification, reacts to taps. |

Our server **never talks to the phone directly** — it can't: phones change
networks, sleep, and sit behind mobile carriers. FCM does the delivering.

---

## The delivery path ("what channel does it use?")

```
 Express server
   │  firebase-admin SDK
   │  HTTPS POST https://fcm.googleapis.com/v1/projects/<project>/messages:send
   │  (authenticated with a service-account key → short-lived OAuth token)
   ▼
 FCM servers (Google) ── stores the message until it can be delivered (up to its time-to-live)
   │
   ├── Android: Google Play services keeps ONE always-open, encrypted
   │            connection between the phone and Google. ALL apps' pushes
   │            share it — that's why push is battery-cheap. FCM sends the
   │            message down this connection; Play services hands it to our app.
   │
   └── iOS:     FCM forwards it to Apple's Push Notification service (APNs),
                which delivers it over Apple's own connection. (Needs an
                Apple Developer account + APNs key; not set up here.)
```

Consequences:
- The app **doesn't keep its own connection open** and doesn't poll.
- Phones **without Google Play services** (e.g. some Huawei models) don't get
  FCM on Android.
- Delivery is **best-effort**: usually seconds, but FCM can delay or drop
  messages. Never put anything in a push that *must* arrive — the database
  stays the source of truth.

---

## Tokens — the phone's push address

When the app starts, the FCM SDK on the phone gets a **registration token**:
a long string that identifies *this app install on this phone*. The server
sends messages **to a token**.

| Event | What happens to the token |
| --- | --- |
| First app start | A token is created |
| Normal use | Stays the same |
| App reinstalled, app data cleared, restored on a new phone | **New token** |
| Firebase rotates it, or it's unused for a long time | New token / old one expires |
| App uninstalled | Old token becomes invalid; FCM tells the server when it tries to send |

So the app must:
1. send its token to our server (Step 4),
2. send it again whenever it changes (`onTokenRefresh`),

and the server must delete tokens that FCM reports as invalid.

Other ways to address phones (not used here): **topics** (every device
subscribed to "promotions") and **conditions** (combinations of topics).

---

## Message types

| Type | Contains | Who handles it |
| --- | --- | --- |
| **Notification message** | `notification: { title, body }` | The **system** shows it when the app isn't in the foreground |
| **Data message** | `data: { key: value, … }` — strings only | **Our code**, always; nothing is shown unless we show it |
| **Both** | title/body **and** data | System shows the notification; our code reads the data (e.g. on tap) |

We use **both**: the text people read ("Netflix renews tomorrow") plus data
our code needs (`type`, `subscriptionId`) to open the right screen.

Limits: the whole payload must stay under **4 KB**, and data values are
**strings**.

---

## What happens in each app state

| App state | Notification shown? | Our Flutter code |
| --- | --- | --- |
| **Foreground** (app open on screen) | **No** — Android doesn't show it automatically | `FirebaseMessaging.onMessage` → *we* show it (with `flutter_local_notifications`) |
| **Background** (in memory, not on screen) | **Yes**, by the system | A top-level background handler may run in its **own isolate** (like the WorkManager task) |
| **Terminated** (closed / swiped away) | **Yes**, by the system | Same background handler |
| **Force-stopped** (Settings → Force stop, or an aggressive battery manager) | **No — nothing is delivered** until the app is opened again | — |

Tapping the notification (Step 7):

| App state when tapped | How the app finds out |
| --- | --- |
| Terminated | `FirebaseMessaging.instance.getInitialMessage()` at startup |
| Background | `FirebaseMessaging.onMessageOpenedApp` |
| Foreground (our own local notification) | `flutter_local_notifications`' tap callback |

---

## Android notification channels

Since Android 8, **every notification belongs to a channel** — a category
like "Subscription reminders". The channel sets the importance (sound,
pop-up) and the **user can mute or tune each channel** in system settings.

- The app **creates** the channel (id, name, importance) at startup.
- The server **names** the channel in each message
  (`android.notification.channel_id`).
- If the channel doesn't exist, Android uses a generic fallback channel.

Ours will be `subscription_reminders` with high importance, so reminders pop
up.

---

## Permission

| Platform | Rule |
| --- | --- |
| Android 12 and older | Allowed by default |
| **Android 13+** | The app must **ask** (`POST_NOTIFICATIONS`). If the user says no, notifications are silently dropped. |
| iOS | Always asked |

Good practice: ask at a meaningful moment (e.g. when turning reminders on)
and explain why first — people who understand the benefit say yes more often.

---

## Delivery options: priority, time-to-live, collapse key

| Option | What it does | For reminders |
| --- | --- | --- |
| **Priority** | `normal`: may wait for the phone to wake up. `high`: delivered right away, even from Doze. High-priority messages that never show a notification get deprioritised by Android. | **high** (it shows a notification) |
| **Time-to-live (TTL)** | How long FCM keeps the message for a phone that's offline. Default 4 weeks; `0` = now or never. | **~12 hours** — a reminder that arrives days late is noise |
| **Collapse key** | A newer message with the same key replaces an older undelivered one. | Per subscription, so an offline phone gets one reminder, not a pile |

---

## Our reminder message

What the server will send (FCM HTTP v1 format; `firebase-admin` builds it):

```json
{
  "message": {
    "token": "<the phone's registration token>",
    "notification": {
      "title": "Netflix renews tomorrow",
      "body": "KES 1,100 · monthly"
    },
    "data": {
      "type": "subscription_reminder",
      "subscriptionId": "3f2b8c1e-6a4d-4f0e-9b7a-2c5d8e1f0a3b"
    },
    "android": {
      "priority": "high",
      "ttl": "43200s",
      "collapse_key": "reminder-3f2b8c1e",
      "notification": { "channel_id": "subscription_reminders" }
    }
  }
}
```

---

## The plan for this app

```
App start
 ├─ ask notification permission (Android 13+)
 ├─ create the "subscription_reminders" channel
 ├─ get the FCM token ──► POST /api/devices { token, reminderTiming }   (again on token refresh)
 │
Server
 ├─ daily job: subscriptions due "tomorrow" or "today" (per device setting),
 │             not already reminded ──► FCM ──► phone
 ├─ test interface: send a reminder for any subscription now
 └─ removes tokens FCM reports as invalid
 │
Phone
 ├─ foreground → show it ourselves     background/closed → system shows it
 └─ tap ──► open that subscription
```

| Step | What we build |
| --- | --- |
| 1 | This page ✅ |
| 2 | Firebase project, permission, print the token, test message from the Firebase console ✅ |
| 3 | Receive in foreground / background / terminated; the notification channel |
| 4 | Register and refresh the token with our server; reminder-timing setting |
| 5 | Server sends a notification with `firebase-admin` |
| 6 | Scheduled reminders + a test interface to send one any time |
| 7 | Tap → open the subscription |
| 8 | Edge cases, tests, docs |

---

## Step 2 — Firebase setup, permission, token

### One-time Firebase setup (per developer)

1. [Firebase console](https://console.firebase.google.com) → **Add project**.
2. **Add app → Android** with package name
   `com.bornmajor.offline_first_subscription_app` (must match exactly).
3. Download **`google-services.json`** into `android/app/`.

`google-services.json` is **git-ignored**: it belongs to *your* Firebase
project, so each developer uses their own. (It isn't a secret like a
password, but keeping project config out of a public repo avoids
confusion and key-scanning alerts.)

### What the code does

| Piece | Where |
| --- | --- |
| Google Services Gradle plugin (reads `google-services.json`) | `android/settings.gradle.kts`, `android/app/build.gradle.kts` |
| `firebase_core`, `firebase_messaging` | `pubspec.yaml` |
| Initialize Firebase → ask permission → get token → watch for a new token | `lib/core/notifications/push_notification_service.dart` |
| Started right after the app shows (not awaited) | `lib/main.dart` |

The app logs:

```
Notification permission: authorized
FCM token: cA1b2…long string…
```

> **Token vs FID:** firebase_messaging 17 deprecates `getToken()` /
> `onTokenRefresh` in favour of a newer "direct send" model
> (`register()` + `onRegistered`, giving a Firebase Installation ID). This
> app keeps the classic token on purpose: it's what the Firebase console's
> test message and firebase-admin's `token` target use, so every step can
> be verified.

### Send a test message from the Firebase console

1. Run the app on the phone and allow notifications; copy the
   `FCM token` line from the log (`adb logcat -s flutter`).
2. **Put the app in the background** (Home button) — in the foreground,
   Android doesn't show notifications automatically (handled in Step 3).
3. Firebase console → **Messaging** (Engage) → **Create your first
   campaign** → **Firebase Notification messages** → enter a title and
   text → **Send test message** → paste the token → **Test**.
4. The notification appears on the phone within seconds.

If nothing arrives: notification permission denied, the app was
force-stopped (by Settings or a battery manager), or the phone has no
Google Play services.

---

## Step 3 — Receive in every app state

| App state | What happens | Code |
| --- | --- | --- |
| **Foreground** | Android shows nothing by itself, so we show it with `flutter_local_notifications` on our channel | `FirebaseMessaging.onMessage` → `_showWhileAppIsOpen()` |
| **Background / closed** | The system shows it on our channel (pops up) | `firebaseMessagingBackgroundHandler` (top-level, own isolate) only logs |

### Our notification channel

```dart
static const reminderChannel = AndroidNotificationChannel(
  'subscription_reminders',          // id — the server sends this as channel_id
  'Subscription reminders',          // name the user sees in Settings
  description: 'Alerts before a subscription renews',
  importance: Importance.high,       // high = pops up on screen
);
```

- Created at every start (creating an existing channel does nothing).
- `AndroidManifest.xml` makes it FCM's **default channel**, so messages that
  don't name a channel (like Firebase console tests) use it too. Before this,
  they went to Android's generic "Miscellaneous" channel, which doesn't pop up.
- After the first install, Android owns the channel's settings: changing the
  importance in code later has no effect unless the app is reinstalled or a new
  channel id is used. The user can change it in Settings → Apps → Subscription
  Tracker → Notifications.

### Android build requirements of `flutter_local_notifications` 23

| Requirement | Where |
| --- | --- |
| Core library desugaring (`isCoreLibraryDesugaringEnabled` + `desugar_jdk_libs`) | `android/app/build.gradle.kts` |
| `compileSdk = 37` (only the compile SDK; target/min unchanged) | `android/app/build.gradle.kts` |
| Android Gradle Plugin 9.1.1+ | `android/settings.gradle.kts` |

### Try it

Send a Firebase console test message:
- **app open** → it pops up (shown by our code); the log shows `Push received in foreground`;
- **app in the background** → it pops up (shown by the system); the log shows
  `Push received in background`;
- **app swiped away** → same as background.

> Troubleshooting: if a build fails in a native step (e.g. stripping debug
> symbols) after dependency changes, stop Gradle (`cd android && gradlew --stop`),
> run `flutter clean`, and build again — a stale or locked build folder is the
> usual cause on Windows.
