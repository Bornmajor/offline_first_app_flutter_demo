# Offline-First Subscription Tracker (Flutter)

A subscription tracker built step by step to learn **offline-first** Flutter
development: the local database is the source of truth, the network is an
optimization, and synchronization happens in the background.

## Features

- Create, edit and delete subscriptions (name, price, category, billing
  cycle, next due date) — **works fully offline**
- Live list that updates itself after every change, from any source
- Automatic two-way sync with a REST API when online: push local changes,
  pull changes made on other devices or the web dashboard
- Conflict handling: last write wins, deletions win, no duplicates on retry
- Sync status in the app bar ("Synced", "Syncing…", "2 changes waiting",
  "Offline") and pull-to-refresh
- Online/offline indicator

## Tech stack

| Area | Tools |
| --- | --- |
| App | Flutter, Dart 3 |
| Local database | [Drift](https://drift.simonbinder.eu) (SQLite) |
| State management | [flutter_bloc](https://pub.dev/packages/flutter_bloc) (Cubit), equatable |
| Networking | [Dio](https://pub.dev/packages/dio) |
| Connectivity | connectivity_plus, internet_connection_checker_plus |
| IDs | uuid (generated on the device) |
| Backend | [Subscription Tracker API](https://github.com/Bornmajor/subscription-tracker-app) — Express + MongoDB |
| Testing | flutter_test, bloc_test, in-memory SQLite, an in-memory fake server |

## Architecture

```
 View (widgets)               draws state, sends user actions
        │ cubit.save(…) / cubit.delete(id)      ▲ BlocBuilder / BlocListener
        ▼                                       │ states
 Cubits                       SubscriptionListCubit · SubscriptionFormCubit
        │ calls                                 ▲ Stream<List<Subscription>>
        ▼                                       │
 SubscriptionRepository       maps Drift rows ⇄ domain entities
        │                                       ▲
        ▼                                       │
 SubscriptionsDao             all SQL for the table (Drift query builder)
        │                                       ▲ .watch() re-emits on every change
        ▼                                       │
 AppDatabase → SQLite file    source of truth
        ▲
        │ push / pull (in the background)
 SyncService ◄──► SubscriptionApi ◄──► Express server
        ▲
 SyncCubit                    decides WHEN to sync, shows the status
```

**Core idea:** everything *writes* to the database; nothing tells anything
else to refresh. `SubscriptionListCubit` listens to `watchAll()`, a Drift
stream that re-emits whenever the `subscriptions` table changes — whoever
changed it (the form, a delete, or the sync engine).

## Getting started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.13`)
- An Android emulator, a physical phone, or a desktop target
- For sync (optional — the app works offline without it):
  [Node.js](https://nodejs.org) 18+ and
  [MongoDB Community Server](https://www.mongodb.com/try/download/community)
  to run the [API server](https://github.com/Bornmajor/subscription-tracker-app)
- Windows only: building with plugins requires **Developer Mode**
  (`start ms-settings:developers`)

### 1. Install

```sh
git clone https://github.com/Bornmajor/offline_first_app_flutter_demo.git
cd offline_first_app_flutter_demo
flutter pub get
dart run build_runner build   # generates the Drift *.g.dart files
```

Re-run `dart run build_runner build` after changing tables or DAOs.

### 2. Start the API server (for sync)

In the [subscription-tracker-app](https://github.com/Bornmajor/subscription-tracker-app)
project (see its README for the `.env` setup):

```sh
npm install
npm run dev     # http://localhost:5000
```

The web dashboard at `http://localhost:5000` lets you change data "from
another device" and watch it sync to the app.

### 3. Run the app

Pass the server's API key (from its `.env`) at build time — it is never
stored in the code:

```sh
flutter run --dart-define=API_KEY=YOUR_KEY
```

| Where the app runs | Server address |
| --- | --- |
| Android emulator | default (`http://10.0.2.2:5000`) — nothing to add |
| Physical phone (same Wi-Fi) | add `--dart-define=API_BASE_URL=http://YOUR_PC_IP:5000` |
| Windows app / iOS simulator | add `--dart-define=API_BASE_URL=http://localhost:5000` |

- Find your PC's IP with `ipconfig` (Windows): "IPv4 Address" under Wi-Fi.
  A physical phone may also need Windows Firewall to allow port 5000.
- Plain `http://` is allowed for Android debug builds and iOS local
  networking only.
- Without `API_KEY` or a reachable server, the app still works fully
  offline; the status line shows "Offline".
- Coming from an older dev build? Uninstall it once — the database schema
  was reset (see [Schema note](#schema-note)).

### 4. Run the tests

```sh
flutter test
```

See [Testing](#testing) for what each test file covers.

## Project structure

```
lib/
├── main.dart                          # Composition root: database, Dio, SyncService, providers
├── core/
│   ├── database/
│   │   ├── app_database.dart          # Drift database, schemaVersion
│   │   └── tables/sync_metadata_table.dart  # key/value store for the pull bookmark
│   ├── enums/billing_cycles.dart
│   ├── network/
│   │   ├── dio_client.dart            # ONE HTTP client: server address, API key, timeouts
│   │   └── network_info.dart          # online/offline detection
│   └── utils/                         # date formatting, form validators
├── shared/widgets/                    # reusable form widgets (text, dropdown, date, button)
└── features/subscriptions/
    ├── data/
    │   ├── local/subscriptions_table.dart     # table definition (+ sync columns)
    │   ├── local/subscriptions_dao.dart       # CRUD queries + sync helpers
    │   ├── remote/subscription_api.dart       # upload / delete / download + JSON
    │   ├── sync/sync_service.dart             # sync() = push, then pull
    │   ├── mappers/subscription_mapper.dart   # SubscriptionRow ⇄ Subscription
    │   └── subscription_repository.dart       # the only data API the screens use
    ├── domain/entities/subscription.dart
    └── presentation/
        ├── cubits/
        │   ├── subscription_list/             # READ + DELETE (home)
        │   ├── subscription_form/             # CREATE + UPDATE (form)
        │   └── sync/                          # WHEN to sync + sync status
        ├── pages/
        │   ├── home_page.dart                 # HomePage (provides cubit) + HomeView (draws)
        │   └── subscription_form_page.dart    # SubscriptionFormPage + SubscriptionFormView
        └── widgets/
```

## Status and roadmap

| Part | Topic | Status |
| --- | --- | --- |
| 1 | Why Drift for offline-first | ✅ Done |
| 2 | [Local database — CRUD with Drift + UI](#part-2--interacting-with-the-local-database-drift) | ✅ Done |
| 3 | [State management with Cubit](#part-3--state-management-with-cubit) | ✅ Done |
| 4 | [Offline sync with the server (push + pull, automatic triggers)](#part-4--offline-sync-with-the-server) | ✅ Done (while the app is open) |
| — | Verify sync end-to-end against the live API | ⏳ Pending |
| — | Data-layer naming cleanup (local/remote data sources, models) | ⏳ Planned |
| 5 | Background sync while the app is closed (`workmanager`) | ⏳ Planned — last stage ([plan](docs/sync-flows.md#not-covered-yet--sync-while-the-app-is-closed)) |

## Documentation

- [Sync Flows](docs/sync-flows.md) — step-by-step walkthroughs: upload, download, sync triggers, offline scenarios, conflicts, and the plan for background sync.
- [Offline-First Concepts](docs/offline-first-concepts.md) — the ideas behind this app (local source of truth, reactive reads, UUIDs, soft delete, migrations, repository mapping, DI, state management, sync), each with a one-sentence summary and where it lives in the code.
- [Tech Stack](docs/tech-stack.md) — the recommended offline-first stack with architecture diagrams and usage notes.

---

## How it works

Deep dives into each part, in the order they were built.

### Part 2 — Interacting with the local database (Drift)

**Goal:** the app stores subscriptions in a local SQLite database and
supports full **CRUD** — create, read, update, delete — entirely offline,
with the UI updating automatically after every change.

#### What the app does

| Operation | In the app | In SQLite |
| --- | --- | --- |
| **Create** | *Create subscription* → fill the form → *Save* | `INSERT` a row with a client-generated UUID |
| **Read** | Home page list (live) | `SELECT … WHERE is_deleted = 0 ORDER BY due_date`, re-run on every change |
| **Update** | Tap a card → edit → *Save changes* | `UPDATE … SET … WHERE id = ? AND is_deleted = 0` |
| **Delete** | *Delete* on a card → confirm | Soft delete: `UPDATE … SET is_deleted = 1` (kept for future sync) |

Data survives app restarts and works in airplane mode.

#### Drift CRUD cheat sheet

| | DAO (Drift) | Repository |
| --- | --- | --- |
| Create | `into(subscriptions).insert(SubscriptionsCompanion.insert(...))` | `create(name:, billingCycle:, …)` |
| Read | `(select(subscriptions)..where(...)..orderBy(...)).watch()` | `watchAll()` |
| Update | `(update(subscriptions)..where((t) => t.id.equals(id))).write(companion)` | `update(subscription)` |
| Delete | same as update, writing `isDeleted: Value(true)` | `delete(id)` |

Key concepts:
- **Row vs Companion** — `SubscriptionRow` is a full row (reading);
  `SubscriptionsCompanion` is a partial row (writing). `Value.absent()` means
  "don't touch this column".
- **`.get()` vs `.watch()`** — read once vs. a live stream.
- **Soft delete** — rows are flagged, not removed, so a future sync engine can
  tell the server about deletions.
- **Migrations** — `schemaVersion` is stored in the SQLite file. In Part 2,
  v1 → v2 added `is_deleted` with `m.addColumn(...)`, keeping existing rows.
  Before Part 4 the schema was squashed back to a clean v1 (no released
  users yet); see [Offline-First Concepts](docs/offline-first-concepts.md#5-schema-migrations).

---

### Part 3 — State management with Cubit

**Goal:** move the screens' logic (listening to data, saving, deleting,
loading and error handling) out of the widgets into Cubits, so widgets only
*draw state* and *send actions*. The data layer from Part 2 is unchanged.

Packages: `flutter_bloc` (Cubit, BlocProvider, BlocBuilder, BlocListener,
RepositoryProvider), `equatable` (state equality), `bloc_test` (dev).

#### Who does what

| Layer | Responsibility |
| --- | --- |
| **Page** (`HomePage`, `SubscriptionFormPage`) | Creates the screen's Cubit with `BlocProvider`, reading the repository from `RepositoryProvider` |
| **View** (`HomeView`, `SubscriptionFormView`) | Draws state, shows dialogs, holds form field values and validation, calls Cubit methods |
| **Cubit** | Logic: listens to the database, saves, deletes, emits states |
| **Repository** | Data access (Part 2) |

#### The two Cubits

| Cubit | Screen | Operations | States |
| --- | --- | --- | --- |
| `SubscriptionListCubit` | Home | Read (`watchSubscriptions`), Delete (`delete`) | `loading` → `success` (items) / `failure` |
| `SubscriptionFormCubit` | Form | Create + Update (`save`) | `idle` → `saving` → `success` / `failure` |

#### Dependency injection

`main()` creates one `AppDatabase` and puts its repository in the widget tree
**above `MaterialApp`**, so every page — including pushed routes — can read it:

```dart
RepositoryProvider<SubscriptionRepository>.value(
  value: db.subscriptionRepository,
  child: const MyApp(),
);

// In a Page:
BlocProvider(
  create: (context) =>
      SubscriptionListCubit(context.read<SubscriptionRepository>())
        ..watchSubscriptions(),
  child: const HomeView(),
);
```

`BlocProvider` closes the Cubit when the page is removed (the list Cubit
cancels its database stream in `close()`).

#### Key concepts

- **State is immutable** — Cubits build the next state with `copyWith` and
  `emit` it; `Equatable` compares states by value.
- **Equal states are skipped** — Cubit doesn't emit a state equal to the
  current one. That's why the list Cubit clears a delete error right after
  reporting it (otherwise a second identical failure would be silent).
- **`BlocBuilder` vs `BlocListener`** — builder *draws* UI from state;
  listener runs *one-off* actions (snackbar, closing the page).
  `buildWhen` / `listenWhen` filter which states each reacts to.
- **One source of truth** — `delete()` and `save()` never edit the list in
  memory; the database changes, `watchAll()` re-emits, the list Cubit emits.
- **Double-tap guard in the Cubit** — `save()` ignores calls while saving.
- **`context.read` rules** — never inside `build()` (use it in callbacks or
  `initState`), and read before any `await`.

---

### Part 4 — Offline sync with the server

**Goal:** keep working offline, and exchange changes with the
[Subscription Tracker API](https://github.com/Bornmajor/subscription-tracker-app)
(Express + MongoDB) whenever the server can be reached — without the screens
knowing anything about the network.

#### One sync = push, then pull

```
sync()
 ├─ PUSH  every row the server doesn't have yet (is_synced = 0)
 │    deleted on the phone → DELETE /api/subscriptions/:id → remove the row
 │    new / edited         → PUT    /api/subscriptions/:id → mark synced
 │                           (or, if the server kept a newer version, take it)
 └─ PULL  GET /api/subscriptions?updatedSince=<bookmark>
      → save each change + the new bookmark (one transaction)
```

All of it lives in [`sync_service.dart`](lib/features/subscriptions/data/sync/sync_service.dart);
[`subscription_api.dart`](lib/features/subscriptions/data/remote/subscription_api.dart)
makes the three HTTP calls and converts JSON.

#### The rules

| Rule | How |
| --- | --- |
| The phone creates ids offline | UUIDs; the server keeps the phone's id |
| Every user change waits to be sent | Local writes set `updatedAt = now`, `isSynced = false` |
| Last write wins | The server compares `updatedAt`; a pulled change never overwrites a *newer* unsynced local edit |
| Deletes win | A deletion anywhere removes the record everywhere |
| An edit during an upload isn't lost | `markSynced` only matches the `updatedAt` that was uploaded |
| Only new changes are downloaded | The "bookmark" (`lastPulledAt`, the server's time) is stored in `sync_metadata` |
| Offline loses nothing | Unsynced rows simply wait; the next sync sends them |

#### When it syncs (`SyncCubit`)

On app start · ~2 s after a local change · when the connection comes back ·
every 5 minutes · on pull-to-refresh or tapping the status line under the
title ("Synced", "Syncing…", "2 changes waiting", "Offline").

#### Edge cases and how they're handled

**Being offline**

| Edge case | How it's solved |
| --- | --- |
| App opened with no internet | Everything still works from SQLite; the sync attempt fails fast and shows "Offline · N changes waiting" |
| Edited offline, app closed, reopened later | Changes are rows with `is_synced = 0` in SQLite, so they survive closing and reboots; uploaded on the next open while online |
| Edited offline and the app is **never** reopened | ⚠️ Not solved yet — stays on the phone. Planned: background sync with `workmanager` (last stage) |
| Connection comes back while the app is open | `NetworkInfo` reports *online* → sync runs immediately |
| Internet works but the server is down | Treated as offline; the 5-minute timer or pull-to-refresh retries |
| Fresh install while offline | Shows only what's created on the phone; the first successful sync downloads the rest |

**During a sync**

| Edge case | How it's solved |
| --- | --- |
| Connection drops mid-sync | Network error stops the sync; unsent rows stay `is_synced = 0`, the bookmark doesn't move |
| Request reached the server but the response was lost | The retry sends the same UUID; the server updates instead of creating a duplicate |
| App killed while saving a download | Rows and bookmark are saved in one transaction — all or nothing, so nothing is skipped |
| User edits a row while it's uploading | `markSynced` only matches the uploaded `updated_at`, so the newer edit stays unsynced and goes next |
| Server rejects one row (e.g. invalid data) | That row is skipped and stays unsynced; the others still sync |
| Two syncs triggered at once | Only one runs (`_isSyncing` guard) |
| Many quick edits | Debounced: one sync ~2 s after the last change |
| Failing syncs retrying forever | Never loops — only the next trigger tries again |

**Conflicts and data correctness**

| Edge case | How it's solved |
| --- | --- |
| Same record edited on two devices | Last write wins on `updatedAt` (server-side for pushes, rule ② for pulls) |
| A download would overwrite a newer local edit | Push runs first, and a pull never replaces a newer unsynced local change |
| Edited here, deleted elsewhere (or the reverse) | Deletes win: the record is removed everywhere |
| Deleted on another device | The server keeps a tombstone (`deletedAt`), so the next pull removes it here |
| Created **and** deleted offline, never uploaded | Only a `DELETE` is sent; the server's `404` counts as done, the row is removed |
| A phone with a wrong clock | The bookmark uses the server's time, so pulls never miss changes (conflict decisions still trust device time — known limitation) |
| Two edits within the same second | Dates stored with milliseconds, so they stay distinguishable |
| Due date shifting a day across time zones | Sent as a plain date (`2026-10-07`), not a timestamp |

**Step-by-step walkthroughs** of upload, download, triggers, offline cases
and conflicts: [docs/sync-flows.md](docs/sync-flows.md).

#### Schema note

Before adding the sync columns, the database schema was squashed back to a
clean v1 (the app had no released users). Uninstall older dev builds once.

---

## Testing

```sh
flutter test
```

Tests run against a real in-memory SQLite database
(`test/helpers/test_database.dart`); widget tests wrap pages with
`testApp()` (`test/helpers/test_app.dart`), which provides the repository
and an unstarted `SyncCubit` the same way `main.dart` does. Sync tests use an
in-memory `FakeServer` (`test/helpers/fake_server.dart`) that follows the
same rules as the real API.

| File | Covers |
| --- | --- |
| `sync/sync_service_test.dart` | Push, pull, conflicts (last write wins, deletes win), edits during upload, offline |
| `sync/subscription_api_json_test.dart` | JSON ⇄ row: plain due dates, UTC milliseconds, tombstones |
| `cubits/sync_cubit_test.dart` | Status changes and each automatic sync trigger |
| `cubits/subscription_list_cubit_test.dart` | Loading → success/failure, live updates, delete via the stream, delete errors reported once each |
| `cubits/subscription_form_cubit_test.dart` | Create/update emit saving → success/failure, double-tap guard, retry after failure |
| `subscription_repository_test.dart` | Each CRUD operation; live stream re-emits; soft delete keeps the row |
| `home_page_list_test.dart` | Empty state, live list, delete with confirm/cancel, failed-delete snackbar |
| `subscription_form_flow_test.dart` | Create and edit through the real form, failed-save snackbar |
| `home_page_network_status_test.dart` | Online/offline indicator |
| `form_validators_test.dart` | Form validation rules |
