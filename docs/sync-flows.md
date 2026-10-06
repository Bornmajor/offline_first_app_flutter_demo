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
- [Not covered yet — sync while the app is closed](#not-covered-yet--sync-while-the-app-is-closed)

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
`SyncService` never syncs on its own.

| # | Trigger | How | Why |
| --- | --- | --- | --- |
| 1 | App opens | `syncNow()` inside `start()` | Send what was left waiting, fetch what changed while closed |
| 2 | A local change | pending count goes **up** → wait 2 s → `syncNow()` | Several quick edits become one sync |
| 3 | Connection comes back | `NetworkInfo` emits *online* → `syncNow()` | Send changes made while offline |
| 4 | Timer | every 5 minutes → `syncNow()` | Pick up changes made on other devices |
| 5 | The user | pull-to-refresh on the list, or tap the status line | "Sync now" |

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
3. **The gap:** if the user **never reopens** the app, the changes stay on the
   phone and never reach the server — other devices won't see them. Closing
   this gap needs background sync (see the last section).

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

## Not covered yet — sync while the app is closed

Everything above runs **while the app is open**. Scenario B.3 shows the gap:
changes made offline reach the server only when the user opens the app again.

**Plan (Part 5): background sync with `workmanager`**

| Platform | What the OS offers | What we'd use it for |
| --- | --- | --- |
| Android | WorkManager: runs tasks after the app is closed, survives reboots, supports "only when connected" | **(a)** a one-off task "sync when connected", queued after each local change · **(b)** a periodic task (minimum every 15 min) to pull |
| iOS | BGTaskScheduler: the system decides **if and when** (often hours later, based on usage) | Opportunistic refresh only — don't rely on it |

How it would work:
1. After a local change, queue **one** unique task "sync-pending" with the
   constraint *network connected* (replacing any queued one).
   The OS runs it as soon as the phone is online — even if the app is closed.
2. Register a periodic task (every 15–30 min, network connected) to pull.
3. The task runs in a **separate isolate** (a separate Dart memory space): it
   can't use the app's objects, so it builds its own `AppDatabase`, Dio client
   and `SyncService`, runs `sync()`, and returns success/failure.
4. The app and the background task may open the same database file at the
   same time, so the database must be opened in **shared mode**
   (Drift's `shareAcrossIsolates`) to avoid conflicting writers.
5. `SyncService` stays exactly the same — background sync is just another
   *trigger*.

```dart
// Sketch only — not implemented yet.
@pragma('vm:entry-point') // keep this function in release builds
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final db = AppDatabase(); // opened in shared mode
    try {
      await SyncService(db.subscriptionsDao, SubscriptionApi(createDioClient()))
          .sync();
      return true;            // success
    } catch (_) {
      return false;           // the OS retries later (with backoff)
    } finally {
      await db.close();
    }
  });
}
```

**Is it needed?** Not for the user's own data: it is never lost and is sent
the next time the app opens online. It matters when **other devices** (or the
dashboard) should see changes made on this phone without waiting for the user
to reopen the app.
