# Offline-First Concepts

The ideas this app relies on to work without a network, each with a one-line
summary, why it matters offline, and where it lives in the code.

For the packages behind these ideas, see [Tech Stack](tech-stack.md).

| Concept | In one sentence |
| --- | --- |
| [Local database as source of truth](#1-local-database-as-source-of-truth) | The UI reads and writes only the local database; the server is synced with later, never waited on. |
| [Reactive reads](#2-reactive-reads-watch) | UI lists listen to database streams that re-emit after every change, so no screen ever has to tell another to refresh. |
| [Client-generated IDs](#3-client-generated-ids-uuid) | Each record gets a UUID on the device when created, so it has a stable, unique id before the server has ever seen it. |
| [Soft delete](#4-soft-delete-and-the-isdeleted-flag) | A hard delete permanently removes a row, while a soft delete keeps the row and sets an `isDeleted` flag that hides it from the user, so an offline app remembers the deletion and can sync it to the server before removing the row for good. |
| [Schema migrations](#5-schema-migrations) | Every table change bumps `schemaVersion` and adds an upgrade step, so users' existing offline data survives app updates. |
| [Repository and mapping](#6-repository-and-mapping) | The presentation layer (Cubits) talks only to a repository that converts database rows into domain entities, so storage details never leak into Cubits or widgets. |
| [Dependency injection](#7-dependency-injection) | One database instance is created in `main()` and provided to the widget tree, so tests can swap in an in-memory database. |
| [State management (Cubit)](#8-state-management-cubit) | Cubits turn the live database stream and user actions into immutable states, so widgets only draw state while the database stays the single source of truth. |
| [Sync: push, pull, bookmark](#9-sync-push-pull-and-the-bookmark) | One sync first pushes every local change the server doesn't have, then pulls every change made elsewhere since the last bookmark; conflicts go to the newest change, and deletions always win. |

---

## 1. Local database as source of truth

**In one sentence:** the UI reads and writes only the local database; the
server is synced with later, never waited on.

**Why it matters offline:** if screens depended on network responses, the app
would stop working the moment the connection drops. Writing locally first
makes every action instant and reliable, online or not.

```
UI ──write──► SQLite (Drift) ◄──sync later──► Server
UI ◄──read─── SQLite (Drift)
```

**In the code:** `SubscriptionRepository` only calls `SubscriptionsDao`; no
widget or repository method touches the network.

---

## 2. Reactive reads (`.watch()`)

**In one sentence:** UI lists listen to database streams that re-emit after
every change, so no screen ever has to tell another to refresh.

**Why it matters offline:** changes come from several places — the user, other
screens, and later the background sync engine pulling server data. With a
live query, the UI shows whatever is in the database, whoever wrote it.

| Drift call | Behaviour |
| --- | --- |
| `.get()` | Runs once, returns a `Future` |
| `.watch()` | Returns a `Stream` that emits now and again after every change to the table |

**In the code:** `SubscriptionsDao.watchAll()` → `SubscriptionRepository.watchAll()`
→ `StreamBuilder` in `HomePage`.

---

## 3. Client-generated IDs (UUID)

**In one sentence:** each record gets a UUID on the device when created, so it
has a stable, unique id before the server has ever seen it.

**Why it matters offline:** an auto-increment id (`1, 2, 3…`) is only unique on
one device — two phones offline would both create record `5`. A UUID is
unique everywhere, and it never changes after sync, so local and server
records can always be matched.

**In the code:** `Subscriptions.id` uses `clientDefault(() => const Uuid().v4())`.

---

## 4. Soft delete and the `isDeleted` flag

**In one sentence:** a hard delete permanently removes a row, while a soft
delete keeps the row and sets an `isDeleted` flag that hides it from the
user, so an offline app remembers the deletion and can sync it to the server
before removing the row for good.

| | Hard delete | Soft delete |
| --- | --- | --- |
| SQL | `DELETE FROM … WHERE id = ?` | `UPDATE … SET is_deleted = 1 WHERE id = ?` |
| Row afterwards | Gone, no trace | Still there, flagged (a *tombstone*) |
| Sync engine can report it | ❌ | ✅ |
| Undo possible | ❌ | ✅ |

**Why it matters offline — what goes wrong with a hard delete:**

1. A record exists on the phone and on the server.
2. The user deletes it while offline; the row is removed.
3. Back online, the sync engine finds nothing to report — the row is gone.
4. The next pull sees the record on the server, assumes it is new, and
   re-inserts it. **The deletion is lost.**

With a soft delete, step 3 finds the flagged row and tells the server.

**The `isDeleted` flag has two jobs:**

1. **Hide the row from the user** — every UI query filters
   `WHERE is_deleted = 0`.
2. **Mark a deletion still waiting to reach the server** — the sync engine
   looks for flagged rows.

**Lifecycle of a deleted row:**

```
visible (is_deleted = 0)
   │ user deletes
   ▼
tombstone (is_deleted = 1, hidden)
   │ sync engine pushes the deletion
   ▼
server confirms
   │
   ▼
hard delete (row removed for good)
```

**Trade-offs:** every query must filter the flag (keep that filter in one
place, the DAO), and tombstones accumulate until they are cleaned up after
sync.

**In the code:**
- `Subscriptions.isDeleted` column
- `SubscriptionsDao.softDelete()` sets the flag
- `SubscriptionsDao.watchAll()` filters it out
- `SubscriptionsDao.updateSubscription()` only matches non-deleted rows, so an
  edit can't revive a deleted record
- `toCompanion()` leaves `isDeleted` absent, so edits never touch the flag

> Status: the whole lifecycle is implemented. `SyncService` pushes the
> deletion, then hard-deletes the tombstone; deletions made elsewhere arrive
> through the pull and are removed locally too.

---

## 5. Schema migrations

**In one sentence:** every table change bumps `schemaVersion` and adds an
upgrade step, so users' existing offline data survives app updates.

**Why it matters offline:** in an offline-first app the device holds data the
server may not have yet. Losing or corrupting the local database on an
update means losing user data for good.

SQLite stores the schema version inside the file; on open, Drift compares it
with `schemaVersion`:

| Situation | What runs |
| --- | --- |
| No file yet (fresh install) | `onCreate` — creates tables in their latest shape |
| File version < `schemaVersion` (app updated) | `onUpgrade` — runs each `if (from < N)` step in order |
| Equal | Nothing |

Rules: never edit an old upgrade step; always add a new one; test it.

**Migration vs. reset:** a migration *upgrades* the existing file and keeps
its data; a reset *deletes* the file and starts over. Online apps can often
reset (the local data is just a cache), but an offline-first app's local
database may hold changes that never reached the server, so released
offline-first apps migrate.

**Before the first release it's fine to squash:** with no real users, the
history of versions can be folded into one clean v1 (dev devices uninstall
the app once). Migrations become mandatory from the first release on.

**In the code:** `AppDatabase.schemaVersion` is `1` and `migration` has only
`onCreate`. During Part 2 the app had a real v1 → v2 migration (`addColumn`
for `is_deleted`, with a test against a real v1 database); in Part 4 the
schema was squashed to v1 before adding the sync columns.

---

## 6. Repository and mapping

**In one sentence:** the presentation layer (Cubits) talks only to a
repository that converts database rows into domain entities, so storage
details never leak into Cubits or widgets.

**Why it matters offline:** the data layer will keep growing — sync columns,
a sync engine, API DTOs. Because Cubits and widgets only know the
`Subscription` entity, none of that changes the presentation layer.

```
Widget ⇄ Cubit ⇄ Subscription ⇄ SubscriptionRepository ⇄ SubscriptionRow / Companion ⇄ DAO ⇄ SQLite
```

**In the code:** `subscription_mapper.dart` — `SubscriptionRow.toEntity()` for
reads and `Subscription.toCompanion()` for writes, implemented as Dart
extension methods because the row class is generated by Drift.

---

## 7. Dependency injection

**In one sentence:** one database instance is created in `main()` and
provided to the widget tree, so tests can swap in an in-memory database.

**Why it matters offline:** offline behaviour (writes, deletes, migrations)
must be testable without a device or network. Injecting the database lets
tests use a fresh in-memory SQLite for every test.

**In the code:**
- `main()` is the composition root: it creates the one `AppDatabase`.
- `RepositoryProvider<SubscriptionRepository>` (from `flutter_bloc`) sits
  above `MaterialApp`, so every page — including routes pushed with
  `Navigator` — can `context.read<SubscriptionRepository>()`.
- Tests use `createTestDatabase()` and wrap pages with `testApp()`
  (`test/helpers/`), which provides a repository backed by in-memory SQLite.

**Why not a service locator (`get_it`)?** `RepositoryProvider` comes with
`flutter_bloc` at no extra cost, keeps dependencies scoped to the tree, and
keeps tests isolated (no global registry to reset). Code without a
`BuildContext` — like a future sync engine — can still receive the
repository through its constructor in `main()`.

---

## 8. State management (Cubit)

**In one sentence:** Cubits turn the live database stream and user actions
into immutable states, so widgets only draw state while the database stays
the single source of truth.

**Why it matters offline:** data changes come from several places — the
user, other screens, and later the sync engine. If each screen kept and
edited its own copy of the list, those copies would drift apart. Here, no
Cubit edits the list in memory: every change goes to the database, and the
list Cubit re-emits what `watchAll()` reports.

```
View ──cubit.delete(id) / cubit.save(…)──► Cubit ──► Repository ──► SQLite
View ◄──BlocBuilder / BlocListener── Cubit ◄──watchAll() stream────────┘
```

| Piece | Job |
| --- | --- |
| **State** | Immutable snapshot of what the screen shows (`status`, `items`, `errorMessage`); `copyWith` builds the next one, `Equatable` compares by value |
| **Cubit** | Holds the current state; methods do the work and `emit` new states |
| **BlocProvider** | Creates a Cubit for a screen and closes it when the screen goes away |
| **BlocBuilder** | Rebuilds UI from state (spinner, list, empty state) |
| **BlocListener** | One-off reactions to a state (snackbar, closing a page) |

Rules this app follows:
- **Never edit the list in the Cubit** — write to the database and let the
  stream deliver the new list.
- **Errors are one-off events** — Cubit skips states equal to the current
  one, so an action error is emitted and then cleared; otherwise a repeated
  failure would show no message.
- **Guard actions in the Cubit, not just the UI** — `save()` ignores calls
  while already saving, preventing duplicate inserts.
- **Stop listening on close** — the list Cubit cancels its database stream
  in `close()`.

**In the code:**
- `SubscriptionListCubit` — READ (`watchSubscriptions`) + DELETE (`delete`)
- `SubscriptionFormCubit` — CREATE + UPDATE (`save`), decides which by
  whether it was given an `initial` subscription
- Page/View split: `HomePage` / `SubscriptionFormPage` create the Cubit;
  `HomeView` / `SubscriptionFormView` draw it
- Tests: `test/cubits/` (with `bloc_test`)

---

## 9. Sync: push, pull, and the bookmark

**In one sentence:** one sync first pushes every local change the server
doesn't have, then pulls every change made elsewhere since the last
bookmark; conflicts go to the newest change, and deletions always win.

**Why it matters offline:** the phone keeps working without a connection,
so changes pile up on both sides (this phone, other phones, the dashboard).
Sync is how they meet again — without losing or duplicating anything.

```
sync()
 ├─ 1. PUSH  rows with is_synced = 0
 │     deleted → DELETE → remove the tombstone
 │     new/edited → PUT → mark synced (or take the server's newer version)
 └─ 2. PULL  changes since the bookmark
       → save them + the new bookmark, together
```

| Idea | In one line |
| --- | --- |
| **Push first** | Our changes reach the server before we download, so the pull can't overwrite them. |
| **`isSynced` flag** | `false` = "the server doesn't have this version yet". Every local write sets it; a successful push clears it. |
| **Bookmark** (`lastPulledAt`) | The server's time of the last download, so the next one only asks for newer changes. Saved in the same transaction as the pulled rows. |
| **Last write wins** | Both sides edited the same record → the edit with the later `updatedAt` is kept. |
| **Deletes win** | A record deleted anywhere is deleted everywhere, even if edited elsewhere later. |
| **Safe retries** | Same id, same data → sending twice gives the same result, so a lost response can't create duplicates. |
| **Server time vs device time** | `updatedAt` (device clock) decides conflicts; the bookmark uses the server's clock, so a wrong phone clock can't make a pull miss changes. |

**When to sync** is a separate question from **how**: `SyncCubit` triggers
`SyncService.sync()` on app start, shortly after a local change, when the
connection returns, every 5 minutes, and on pull-to-refresh.

**In the code:**
- `SyncService` (`data/sync/sync_service.dart`) — push, pull, and the one
  rule for applying a server version
- `SubscriptionApi` (`data/remote/subscription_api.dart`) — the three HTTP
  calls and the JSON format
- `SubscriptionsDao` SYNC section — `getUnsynced`, `markSynced`,
  `saveFromServer`, `hardDelete`, bookmark get/set
- `SyncCubit` (`presentation/cubits/sync/`) — triggers and status
- Tests: `test/sync/` with an in-memory `FakeServer`, and
  `test/cubits/sync_cubit_test.dart`

**While the app is closed:** a `workmanager` task runs the same `sync()` in
its own isolate (Android; iOS configured but untested). The app and the
background task hand over on pause/resume, and a foreground heartbeat stops
them syncing at the same time — see
[Sync Flows → Background sync](sync-flows.md#background-sync-part-5).
