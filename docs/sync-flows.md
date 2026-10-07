# Sync Flows — Step by Step

How the app keeps working offline and exchanges changes with the
[Subscription Tracker API](https://github.com/Bornmajor/subscription-tracker-app)
when it can. Each flow below is a numbered list of what actually happens, with
the code that does it.

- [The big picture](#the-big-picture)
- [What the database remembers](#what-the-database-remembers)
- [Flow 1 — The user changes something](#flow-1--the-user-changes-something)
- [Flow 2 — Upload (push)](#flow-2--upload-push)
- [Flow 3 — Download (pull)](#flow-3--download-pull)
- [Flow 4 — What triggers a sync](#flow-4--what-triggers-a-sync)
- [Flow 5 — Offline scenarios](#flow-5--offline-scenarios)
- [Flow 6 — Conflicts: protecting newer local data](#flow-6--conflicts-protecting-newer-local-data)
- [Background sync (Part 5)](#background-sync-part-5)
- [Testing background sync on Android](#testing-background-sync-on-android)

---

## The big picture

```
 Screens ──write──► SQLite (source of truth) ◄──watchAll()── Screens redraw
                          ▲      │
             pull: save   │      │ push: rows with is_synced = 0
                          │      ▼
                     SyncService.sync()  ◄── SyncCubit: WHEN to sync
                          ▲      │
                          │      ▼
                     SubscriptionApi (HTTP) ◄──► Express server
```

- Screens **only** read and write SQLite. Saving never waits for the network.
- `SyncService` is the **only** code that talks to the server.
- One sync = **push, then pull**.

| Piece | File | Job |
| --- | --- | --- |
| `SyncService` | `lib/features/subscriptions/data/sync/sync_service.dart` | HOW to sync: push, then pull |
| `SubscriptionApi` | `lib/features/subscriptions/data/remote/subscription_api.dart` | The 3 HTTP calls + JSON |
| `SubscriptionsDao` (SYNC section) | `lib/features/subscriptions/data/local/subscriptions_dao.dart` | Database helpers for sync |
| `SyncCubit` | `lib/features/subscriptions/presentation/cubits/sync/sync_cubit.dart` | WHEN to sync + status for the UI |

---

## What the database remembers

Every subscription row has three sync columns, and there is one bookmark:

| Column / value | Meaning |
| --- | --- |
| `is_synced` | `0` = the server doesn't have this version yet. `1` = in step with the server. |
| `updated_at` | When this phone last changed the row (used for "last write wins"). |
| `is_deleted` | `1` = deleted by the user, kept as a *tombstone* until the server knows. |
| `lastPulledAt` (table `sync_metadata`) | **The bookmark:** server time of the last download. |

Because all of this is stored in SQLite, it **survives closing the app,
restarting the phone, and being offline for days**.

---

## Flow 1 — The user changes something

Works the same online or offline.

1. The user creates, edits, or deletes a subscription.
2. The DAO saves it and stamps the row through `_asLocalChange()`:
   `updated_at = now`, `is_synced = 0` (a delete also sets `is_deleted = 1`).
3. `watchAll()` re-emits → the list updates **immediately**.
4. The pending count goes up → the status shows **"1 change waiting"**.
5. `SyncCubit` schedules a sync ~2 seconds later (see [Flow 4](#flow-4--what-triggers-a-sync)).

Nothing here needs the server. The change is safe the moment step 2 finishes.

---

## Flow 2 — Upload (push)

Runs first in every sync. Example: "Netflix" was created offline.

| id | name | updated_at | is_synced | is_deleted |
| --- | --- | --- | --- | --- |
| `3f2b…0a3b` | Netflix | 09:30:15.123 | **0** | 0 |

1. **Find what to send.** `getUnsynced()` → every row with `is_synced = 0`.
2. **For each row:**
   - **Deleted** (`is_deleted = 1`):
     1. `DELETE /api/subscriptions/3f2b…0a3b` (body: `updatedAt`).
        A `404` counts as success (the server never had it).
     2. `hardDelete()` — the tombstone has done its job.
   - **New or edited:**
     1. `PUT /api/subscriptions/3f2b…0a3b` with the row as JSON — under the
        **phone's own id**, so a retry can never create a duplicate.
     2. Server answers `{"applied": true, …}` → `markSynced(id, updatedAt)`
        → `is_synced = 1`.
     3. Server answers `{"applied": false, "subscription": …}` (it kept a
        newer or deleted version) → save the server's version instead
        ([Flow 6](#flow-6--conflicts-protecting-newer-local-data)).
3. **If a request fails:**
   - **No response** (offline, server down) → **stop the whole sync**. Every
     row not yet sent keeps `is_synced = 0` and waits for the next sync.
   - **Server rejects one row** (e.g. `400`) → skip it, continue with the
     others. It stays unsynced.

```dart
for (final row in await _dao.getUnsynced()) {
  if (row.isDeleted) {
    await _api.delete(row);
    await _dao.hardDelete(row.id);
  } else {
    final response = await _api.upload(row);
    if (response['applied'] == true) {
      await _dao.markSynced(row.id, row.updatedAt);
    } else {
      await _saveServerVersion(response['subscription']);
    }
  }
}
```

**Edited during the upload?** `markSynced` only matches the `updated_at` that
was uploaded. If the user saved a newer edit meanwhile, nothing matches, the
row stays unsynced, and the newer edit is sent next time.

---

## Flow 3 — Download (pull)

Runs after a successful push. It fetches changes made **elsewhere** — another
phone or the web dashboard.

1. **Read the bookmark** — `getLastPulledAt()`.
   `null` on the very first sync.
2. **Ask the server**
   - first sync: `GET /api/subscriptions` → every live subscription
   - later: `GET /api/subscriptions?updatedSince=<bookmark>` → only changes
     after the bookmark, **including deletions** (records with `deletedAt`)
3. **Apply the changes and move the bookmark — in one transaction:**
   1. for each subscription: `_saveServerVersion(json)` (the rule below)
   2. `setLastPulledAt(serverTime)`
   If the app is killed halfway, **nothing** is saved and the bookmark doesn't
   move, so the next sync downloads the same changes again. Nothing is skipped.
4. `watchAll()` re-emits → the list shows the new data. The screens never
   know it came from the server.

**The one rule for a server version** (`_saveServerVersion`):

| # | Situation | Action |
| --- | --- | --- |
| ① | Server says it's **deleted** | Delete it here too (*deletes win*) |
| ② | This phone has an **unsynced** change that is **newer** | Keep mine; the next push sends it |
| ③ | Anything else | Save the server's version (`is_synced = 1`) |

**Example timeline**

| Server time | Event | Pull | Returned | Bookmark |
| --- | --- | --- | --- | --- |
| 09:00 | First sync | `GET …` | everything | 09:00 |
| 09:20 | Spotify price edited in the dashboard | | | |
| 09:25 | Hulu deleted on another phone | | | |
| 09:30 | Sync | `GET …?updatedSince=09:00` | Spotify (③ save), Hulu tombstone (① delete) | 09:30 |
| 09:35 | Sync, nothing new | `GET …?updatedSince=09:30` | `[]` | 09:35 |

The bookmark uses the **server's** clock, so a phone with a wrong clock can
never make a pull miss changes.

---

## Flow 4 — What triggers a sync

`SyncCubit.start()` runs once when the app opens and sets up every trigger.
`SyncService` never syncs on its own. Triggers 1–5 act **only while the app
is on screen**; trigger 6 takes over when it isn't.

| # | Trigger | How | Why |
| --- | --- | --- | --- |
| 1 | App opens, or comes back on screen | `syncNow()` in `start()` / `appResumed()` | Send what was left waiting, fetch what changed meanwhile |
| 2 | A local change | pending count goes **up** → wait 2 s → `syncNow()` | Several quick edits become one sync |
| 3 | Connection comes back | `NetworkInfo` emits *online* → `syncNow()` | Send changes made while offline |
| 4 | Timer | every 5 minutes → `syncNow()` | Pick up changes made on other devices |
| 5 | The user | pull-to-refresh on the list, or tap the status line | "Sync now" |
| 6 | App **not** on screen (switched away, closed, killed) | WorkManager runs `runBackgroundSync()` — see [Background sync](#background-sync-part-5) | Send changes left behind; catch up while closed |

Guards:
- Only **one** sync runs at a time (`_isSyncing` in `SyncService`, and the
  `syncing` status in `SyncCubit`).
- The count going **down** (during a push) does **not** start another sync.
- Failures don't retry in a loop — only the next trigger tries again.

**Status line** under the title: *Synced* · *Syncing…* · *2 changes waiting* ·
*Offline · 1 change waiting* · *Sync failed · tap to retry*.

---

## Flow 5 — Offline scenarios

### A. The app is opened with no internet
1. `start()` → `syncNow()` → the first upload fails quickly (no connection,
   or the 5-second connect timeout).
2. The sync stops; status: **"Offline · N changes waiting"**. Pull doesn't run.
3. The user keeps working normally — every change is saved in SQLite
   (Flow 1). Each new change tries one sync, which fails fast again.
4. When the connection returns, trigger 3 runs a full sync → **"Synced"**.

### B. Changes made offline, then the app is closed, then reopened
1. The changes are rows with `is_synced = 0` in the SQLite file. Closing the
   app, or even restarting the phone, doesn't lose them.
2. The user reopens the app:
   - **Now online** → trigger 1 (app opens) pushes them right away.
   - **Still offline** → scenario A: they keep waiting, and are sent as soon
     as the connection returns while the app is open.
3. **If the user never reopens the app:** when it left the screen, a
   background task "sync when connected" was queued. Android runs it once
   there's internet — even with the app closed — and the changes reach the
   server (see [Background sync](#background-sync-part-5)). On iOS this is
   best-effort; otherwise they're sent on the next open.

### C. The connection drops in the middle of a sync
1. Rows already uploaded were marked synced; the rest keep `is_synced = 0`.
2. The network error stops the sync; pull doesn't run, the bookmark doesn't move.
3. The next sync continues where it stopped. A row whose response was lost
   is simply sent again under the same id — the server updates instead of
   duplicating.

### D. Internet works but the server is down
Same as offline: no response → status **"Offline"**; the 5-minute timer or a
pull-to-refresh tries again.

### E. A fresh install while offline
There is no server data on the phone yet. The list only shows what the user
creates there; the first successful sync downloads everything else.

---

## Flow 6 — Conflicts: protecting newer local data

Three layers stop a download from overwriting newer local work:

1. **Push before pull.** By the time we download, the server already has our
   changes. If the push fails offline, the pull doesn't run at all.
2. **Rule ②** — a pulled version never replaces an **unsynced** local change
   that is **newer**.
3. **`markSynced` compares `updated_at`** — an edit made during the upload
   stays unsynced, so rule ② protects it in the pull that follows.

| Phone | Server | Result |
| --- | --- | --- |
| Synced, unchanged | Edited elsewhere | Server version saved |
| Unsynced edit at 10:05 | Edit at 10:00 | **Mine kept**, pushed next |
| Unsynced edit at 10:00 | Edit at 10:05 | Server version saved (newer wins) |
| Unsynced new row | Doesn't have it | Untouched |
| Anything | Deleted | Removed (deletes win) |

**Limits of last-write-wins**
- The newer **whole record** wins: if you changed the price and someone else
  the name, one of those changes is lost. Alternatives: per-field merging,
  keeping both and asking the user, or server version numbers.
- `updated_at` comes from the phone's clock; a phone whose clock is far off can
  win or lose conflicts unfairly. (Pulls are unaffected — they use server time.)

---

## Background sync (Part 5)

Flows 1–6 run **while the app is open**. Background sync covers the rest:
changes left behind when the user leaves the app reach the server **even if
the app is closed or killed**, and changes made elsewhere are picked up
roughly every 30 minutes.

It uses [`workmanager`](https://pub.dev/packages/workmanager)
(Android WorkManager / iOS BGTaskScheduler) and runs the **same**
`SyncService.sync()` — background sync is just another trigger.

| Piece | File | Job |
| --- | --- | --- |
| `callbackDispatcher()` | `lib/features/subscriptions/data/sync/background_sync.dart` | Entry point the OS calls in a fresh isolate |
| `runBackgroundSync()` | same | Opens its own database, checks the heartbeat, runs `sync()`, returns true/false |
| `BackgroundSyncScheduler` | same | Registers the periodic task; queues/cancels the one-off task |
| `SyncCubit.appPaused()` / `appResumed()` | `presentation/cubits/sync/sync_cubit.dart` | The handoff between the app and the background |
| `SyncLifecycleListener` | `presentation/widgets/sync_lifecycle_listener.dart` | Forwards Flutter's pause/resume events to `SyncCubit` |

### The two background tasks

| Task | When it's queued | When it runs | Cancelled? |
| --- | --- | --- | --- |
| **One-off** "sync when connected" | When the app leaves the screen **with changes waiting** | As soon as there's internet — even if the app is closed | Yes, when the app comes back (the app syncs itself) |
| **Periodic** "sync every ~30 min" | Once, at app start (keeps its schedule across launches) | Roughly every 30 min with internet — Android decides the exact moment; iOS treats it as a hint | **Never** — it must survive the app being killed; while the app is open it simply skips |

Both require internet, and a failed run returns `false` so the OS retries
later with growing delays (backoff).

### Step by step: the user edits offline and closes the app

1. The user edits a subscription in airplane mode → saved, `is_synced = 0`
   (Flow 1).
2. They switch away → `appPaused()`:
   - foreground timers stop,
   - the heartbeat is set to "expired now",
   - changes are waiting → the one-off task is queued.
3. They swipe the app away. Nothing is lost — the task is queued with the OS.
4. Airplane mode goes off → Android starts a **fresh Dart isolate** and calls
   `callbackDispatcher()` → `runBackgroundSync()`:
   1. opens its own `AppDatabase`, Dio client and `SyncService`,
   2. heartbeat expired → its turn,
   3. `sync()` → push, then pull (Flows 2–3),
   4. returns `true` (or `false` → retried later),
   5. closes the database.
5. The change is on the server; the dashboard and other devices see it.
6. Later the user opens the app → `appResumed()` refreshes the list from the
   database, so it already shows everything.

### Never sync in the foreground and the background at once

The app (`SyncCubit`) and the background task each run their own
`SyncService` in a different isolate, so the in-memory `_isSyncing` guard
can't see the other side. The rule is: **the app syncs while it is visible;
the background task syncs only while it is not** — including after the app
was killed.

**1. Hand over on the app lifecycle** (`AppLifecycleListener`)

| App becomes | Action |
| --- | --- |
| Visible (*resumed*) | Cancel the queued one-off task → refresh live queries → heartbeat on → `SyncCubit` triggers on → sync now |
| Not visible (*paused*) | `SyncCubit` timers off → heartbeat expired → queue the one-off task if changes are waiting |

**2. A heartbeat, because "killed" can't be detected**

The OS never announces that it killed the app, and the periodic task can
fire while the app is open. So while visible, the app writes
`foregroundActiveUntil = now + 2 min` to `sync_metadata` every minute. The
background task checks it first:

```dart
final activeUntil = await db.subscriptionsDao.getForegroundActiveUntil();
if (activeUntil != null && activeUntil.isAfter(DateTime.now())) {
  return true;            // the app is open and syncing itself → skip
}
await SyncService(db.subscriptionsDao, api).sync(); // our turn
```

A killed app stops renewing the heartbeat, so it **expires by itself** and
background sync is allowed again. (A plain "app is open" flag would stay
stuck after a crash.)

**3. Safe overlap as the last resort**

In the few seconds around a switch both sides could still overlap. That's
harmless: uploads are safe to repeat (same id → update, no duplicate),
last-write-wins still decides conflicts, and the database is set up for
two users at once:

| Setting (`app_database.dart`) | Why |
| --- | --- |
| `shareAcrossIsolates: true` | Within one engine, the app and the task share **one** connection |
| `PRAGMA journal_mode = WAL` | A background task usually runs in its **own** engine (own connection); readers and a writer can then work together |
| `PRAGMA busy_timeout = 5000` | A second writer waits up to 5 s for its turn instead of failing with "database is locked" |

Because a change made by another engine can't notify the app's live
queries, `appResumed()` calls `refreshLiveQueries()` so the list shows it.

**Timeline**

| Time | Event | Who syncs |
| --- | --- | --- |
| 10:00 | App open, heartbeat "until 10:02" | App |
| 10:01 | Periodic task fires, heartbeat fresh | Nobody extra — task skips |
| 10:03 | User switches to another app | Timers off, one-off task queued |
| 10:04 | Phone gets internet | Background (heartbeat expired) |
| 10:10 | Android kills the app (no callback) | — |
| 10:30 | Periodic task fires | Background (heartbeat long expired) |
| 11:00 | User opens the app | App (queued task cancelled, heartbeat renewed) |

### Limits

| Platform | What to expect |
| --- | --- |
| **Android** | Reliable, but timing is up to the OS: Doze, battery saver and rarely used apps get fewer runs. **Force stop** cancels all tasks until the app is opened again. Phone makers' battery managers (Infinix/Tecno, Xiaomi, Oppo…) may block it — see the settings below. |
| **iOS** | Best-effort and **untested** (needs a Mac): iOS decides if and when to run, runs nothing after the user swipes the app away, and the one-off task only gets a short window right after leaving the app. The sync on the next app open still covers everything. Setup: `UIBackgroundModes` → `fetch` and `BGTaskSchedulerPermittedIdentifiers` in `ios/Runner/Info.plist`, registration in `ios/Runner/AppDelegate.swift`. |

---

## Testing background sync on Android

Package name: `com.example.offline_first_app_flutter_demo`. Use a **debug**
build (release blocks plain `http://`).

### 1. See background runs in the log

`runBackgroundSync()` prints one line per run:
`Background sync done`, `… skipped: the app is in the foreground`, or
`… failed, will retry: …`.

```sh
adb logcat -s flutter
```

### 2. The main scenario

1. Start the API server and run the app on the phone (README → Getting started).
2. Turn on **airplane mode**, create a subscription, then **swipe the app away**.
3. Turn airplane mode **off** and wait a minute or two.
4. The log shows `Background sync done`, and the subscription appears in the
   dashboard — without opening the app.

### 3. Don't want to wait? Force the task to run

WorkManager schedules work through Android's JobScheduler. Find the app's
job ids, then run one immediately (`-f` ignores constraints like "needs
internet"):

```sh
adb shell dumpsys jobscheduler | grep -A2 offline_first_app_flutter_demo
adb shell cmd jobscheduler run -f com.example.offline_first_app_flutter_demo JOB_ID
```

(On Windows without Git Bash, use `findstr offline_first_app_flutter_demo` instead of `grep`.)

WorkManager can also print what it has scheduled (debug builds):

```sh
adb shell am broadcast -a "androidx.work.diagnostics.REQUEST_DIAGNOSTICS" -p "com.example.offline_first_app_flutter_demo"
adb logcat -s WM-DiagnosticsWrkr
```

### 4. Simulate Doze (idle phone)

```sh
adb shell dumpsys deviceidle force-idle
adb shell dumpsys deviceidle unforce
```

### 5. Infinix / XOS battery settings

XOS can block background work for apps it considers unimportant. If
background runs never appear in the log, allow the app to run in the
background (menu names vary by XOS version):

- **Settings → Apps → the app → Battery** → *Allow background activity* /
  *No restrictions*
- **Phone Master → Auto-start management** (or *App launch*) → enable the app
- Turn off **Power saving / Ultra power saving** while testing
- Avoid one-tap "clean / boost" in Phone Master — it can force-stop the app,
  which cancels its scheduled work

## Future: notifications for background sync

`workmanager` runs code only; it has no notification interface. Showing one
(e.g. "3 changes couldn't be uploaded for 2 days") is a separate piece, usually
`flutter_local_notifications`, initialised inside the background isolate and
needing notification permission (Android 13+ and iOS). Routine sync should
stay silent; notifications are planned for later, once the app is bigger and
has events worth telling the user about.
