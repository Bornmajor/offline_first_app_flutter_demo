# offline_first_app_flutter_demo

A subscription tracker built step by step to learn **offline-first** Flutter
development: local data is the source of truth, the network is an
optimization, and synchronization happens in the background.

## Documentation

- [Tech Stack](docs/tech-stack.md) — recommended offline-first stack (Riverpod, Dio, Drift, Freezed, connectivity_plus, workmanager, flutter_secure_storage, talker) with architecture diagrams and usage notes.
- [Offline-First Concepts](docs/offline-first-concepts.md) — the ideas behind this app (local source of truth, reactive reads, UUIDs, soft delete, migrations, repository mapping, DI, state management), each with a one-sentence summary and where it lives in the code.

## Learning roadmap

| Part | Topic | Status |
| --- | --- | --- |
| 1 | Why Drift for offline-first | ✅ |
| 2 | [Interacting with the local database — CRUD with Drift + UI](#part-2--interacting-with-the-local-database-drift) | ✅ |
| 3 | [State management with Cubit on top of the same data layer](#part-3--state-management-with-cubit) | ✅ |
| 4 | Offline sync mechanism (push/pull with a server) | ⏳ |

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
```

**Core idea:** everything *writes* to the database; nothing tells anything
else to refresh. `SubscriptionListCubit` listens to `watchAll()`, a Drift
stream that re-emits whenever the `subscriptions` table changes — whoever
changed it (the form, a delete, and later the sync engine).

## Project structure

```
lib/
├── main.dart                          # Composition root: one AppDatabase + RepositoryProvider
├── core/
│   ├── database/app_database.dart     # Drift database, schemaVersion, migrations
│   ├── enums/billing_cycles.dart
│   ├── network/                       # online/offline indicator
│   └── utils/                         # date formatting, form validators
├── shared/widgets/                    # reusable form widgets (text, dropdown, date, button)
└── features/subscriptions/
    ├── data/
    │   ├── local/subscriptions_table.dart     # table definition
    │   ├── local/subscriptions_dao.dart       # CRUD queries
    │   ├── mappers/subscription_mapper.dart   # SubscriptionRow ⇄ Subscription
    │   └── subscription_repository.dart       # the only data API the app uses
    ├── domain/entities/subscription.dart
    └── presentation/
        ├── cubits/
        │   ├── subscription_list/             # READ + DELETE (home)
        │   └── subscription_form/             # CREATE + UPDATE (form)
        ├── pages/
        │   ├── home_page.dart                 # HomePage (provides cubit) + HomeView (draws)
        │   └── subscription_form_page.dart    # SubscriptionFormPage + SubscriptionFormView
        └── widgets/
```

---

## Part 2 — Interacting with the local database (Drift)

**Goal:** the app stores subscriptions in a local SQLite database and
supports full **CRUD** — create, read, update, delete — entirely offline,
with the UI updating automatically after every change.

### What the app does

| Operation | In the app | In SQLite |
| --- | --- | --- |
| **Create** | *Create subscription* → fill the form → *Save* | `INSERT` a row with a client-generated UUID |
| **Read** | Home page list (live) | `SELECT … WHERE is_deleted = 0 ORDER BY due_date`, re-run on every change |
| **Update** | Tap a card → edit → *Save changes* | `UPDATE … SET … WHERE id = ? AND is_deleted = 0` |
| **Delete** | *Delete* on a card → confirm | Soft delete: `UPDATE … SET is_deleted = 1` (kept for future sync) |

Data survives app restarts and works in airplane mode.

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
- **Migrations** — `schemaVersion` is stored in the SQLite file. In Part 2,
  v1 → v2 added `is_deleted` with `m.addColumn(...)`, keeping existing rows.
  Before Part 4 the schema was squashed back to a clean v1 (no released
  users yet); see [Offline-First Concepts](docs/offline-first-concepts.md#5-schema-migrations).

---

## Part 3 — State management with Cubit

**Goal:** move the screens' logic (listening to data, saving, deleting,
loading and error handling) out of the widgets into Cubits, so widgets only
*draw state* and *send actions*. The data layer from Part 2 is unchanged.

Packages: `flutter_bloc` (Cubit, BlocProvider, BlocBuilder, BlocListener,
RepositoryProvider), `equatable` (state equality), `bloc_test` (dev).

### Who does what

| Layer | Responsibility |
| --- | --- |
| **Page** (`HomePage`, `SubscriptionFormPage`) | Creates the screen's Cubit with `BlocProvider`, reading the repository from `RepositoryProvider` |
| **View** (`HomeView`, `SubscriptionFormView`) | Draws state, shows dialogs, holds form field values and validation, calls Cubit methods |
| **Cubit** | Logic: listens to the database, saves, deletes, emits states |
| **Repository** | Data access (Part 2) |

### The two Cubits

| Cubit | Screen | Operations | States |
| --- | --- | --- | --- |
| `SubscriptionListCubit` | Home | Read (`watchSubscriptions`), Delete (`delete`) | `loading` → `success` (items) / `failure` |
| `SubscriptionFormCubit` | Form | Create + Update (`save`) | `idle` → `saving` → `success` / `failure` |

### Dependency injection

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

### Key concepts

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

## Running

```sh
flutter pub get
dart run build_runner build   # regenerate *.g.dart after changing tables/DAOs
flutter run
```

> Windows: building with plugins requires Developer Mode
> (`start ms-settings:developers`).

## Tests

```sh
flutter test
```

Tests run against a real in-memory SQLite database
(`test/helpers/test_database.dart`); widget tests wrap pages with
`testApp()` (`test/helpers/test_app.dart`), which provides the repository
the same way `main.dart` does.

| File | Covers |
| --- | --- |
| `cubits/subscription_list_cubit_test.dart` | Loading → success/failure, live updates, delete via the stream, delete errors reported once each |
| `cubits/subscription_form_cubit_test.dart` | Create/update emit saving → success/failure, double-tap guard, retry after failure |
| `subscription_repository_test.dart` | Each CRUD operation; live stream re-emits; soft delete keeps the row |
| `home_page_list_test.dart` | Empty state, live list, delete with confirm/cancel, failed-delete snackbar |
| `subscription_form_flow_test.dart` | Create and edit through the real form, failed-save snackbar |
| `home_page_network_status_test.dart` | Online/offline indicator |
| `form_validators_test.dart` | Form validation rules |
