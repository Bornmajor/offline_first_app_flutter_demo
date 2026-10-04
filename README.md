# offline_first_app_flutter_demo

A subscription tracker built step by step to learn **offline-first** Flutter
development: local data is the source of truth, the network is an
optimization, and synchronization happens in the background.

## Documentation

- [Tech Stack](docs/tech-stack.md) — recommended offline-first stack (Riverpod, Dio, Drift, Freezed, connectivity_plus, workmanager, flutter_secure_storage, talker) with architecture diagrams and usage notes.

## Learning roadmap

| Part | Topic | Status |
| --- | --- | --- |
| 1 | Why Drift for offline-first | ✅ |
| 2 | **Interacting with the local database — CRUD with Drift + UI** | ✅ this branch |
| 3 | State management (Bloc) on top of the same data layer | ⏳ |
| 4 | Offline sync mechanism (push/pull with a server) | ⏳ |

---

## Part 2 — Interacting with the local database (Drift)

**Goal:** the app stores subscriptions in a local SQLite database and
supports full **CRUD** — create, read, update, delete — entirely offline,
with the UI updating automatically after every change. No state-management
library and no server yet: just Drift and Flutter.

### What the app does

| Operation | In the app | In SQLite |
| --- | --- | --- |
| **Create** | *Create subscription* → fill the form → *Save* | `INSERT` a row with a client-generated UUID |
| **Read** | Home page list (live) | `SELECT … WHERE is_deleted = 0 ORDER BY due_date`, re-run on every change |
| **Update** | Tap a card → edit → *Save changes* | `UPDATE … SET … WHERE id = ? AND is_deleted = 0` |
| **Delete** | *Delete* on a card → confirm | Soft delete: `UPDATE … SET is_deleted = 1` (kept for future sync) |

Data survives app restarts and works in airplane mode.

### Architecture

```
 UI (pages / widgets)         knows only: Subscription (domain entity)
        │  calls                 ▲ Stream<List<Subscription>>
        ▼                        │
 SubscriptionRepository       maps Drift rows ⇄ entities
        │                        ▲
        ▼                        │
 SubscriptionsDao             all SQL for the table (Drift query builder)
        │                        ▲ .watch() re-emits on every table change
        ▼                        │
 AppDatabase → SQLite file    source of truth
```

**Core idea:** screens only *write* to the database; they never tell each
other to refresh. The home page listens to `watchAll()`, a Drift stream that
re-emits whenever the `subscriptions` table changes — whoever changed it.

### Project structure

```
lib/
├── main.dart                              # Composition root: one AppDatabase, injected down
├── core/
│   ├── database/app_database.dart         # Drift database, schemaVersion, migrations
│   ├── enums/billing_cycles.dart
│   ├── network/                           # online/offline indicator
│   └── utils/                             # date formatting, form validators
├── shared/widgets/                        # reusable form widgets (text, dropdown, date, button)
└── features/subscriptions/
    ├── data/
    │   ├── local/subscriptions_table.dart # table definition
    │   ├── local/subscriptions_dao.dart   # CRUD queries
    │   ├── mappers/subscription_mapper.dart  # SubscriptionRow ⇄ Subscription
    │   └── subscription_repository.dart  # the only API the UI uses
    ├── domain/entities/subscription.dart
    └── presentation/
        ├── pages/home_page.dart           # live list, delete, open edit
        ├── pages/subscription_form_page.dart  # create + edit
        └── widgets/
```

### Drift CRUD cheat sheet

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
- **Migrations** — `schemaVersion` is stored in the SQLite file. v1 → v2 added
  `is_deleted` with `m.addColumn(...)`; existing rows are kept.
- **Dependency injection** — `main()` creates one `AppDatabase` and passes the
  repository down through constructors, so tests can inject an in-memory DB.

### Running

```sh
flutter pub get
dart run build_runner build   # regenerate *.g.dart after changing tables/DAOs
flutter run
```

> Windows: building with plugins requires Developer Mode
> (`start ms-settings:developers`).

### Tests

```sh
flutter test
```

Tests run against a real in-memory SQLite database (`test/helpers/test_database.dart`):

| File | Covers |
| --- | --- |
| `subscription_repository_test.dart` | Each CRUD operation; live stream re-emits; soft delete keeps the row |
| `database_migration_test.dart` | Upgrading a real v1 database to v2 keeps existing data |
| `home_page_list_test.dart` | Empty state, live list, delete with confirm/cancel |
| `subscription_form_flow_test.dart` | Create and edit through the real form |
| `home_page_network_status_test.dart` | Online/offline indicator |
| `form_validators_test.dart` | Form validation rules |
