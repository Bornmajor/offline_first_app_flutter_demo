import 'package:drift/drift.dart';
import 'package:offline_first_app_flutter_demo/core/enums/billing_cycles.dart';
import 'package:uuid/uuid.dart';

/// Describes the `subscriptions` SQL table in Dart.
/// From this class, build_runner generates:
///   • `SubscriptionRow`         — one full row (used when READING)
///   • `SubscriptionsCompanion`  — a partial row (used when WRITING)
///
/// `@DataClassName` renames the generated row class, otherwise Drift would
/// call it `Subscription` and clash with our domain entity.
@DataClassName('SubscriptionRow')
class Subscriptions extends Table {
  /// Primary key. A UUID generated on the device (clientDefault), so ids are
  /// unique even when created offline on several devices.
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  /// `withLength` adds a check: empty names are rejected by the database.
  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// Stored as the enum name ("monthly"); read back as [BillingCycles].
  TextColumn get billingCycle => textEnum<BillingCycles>()();

  /// Stored as a number in SQLite; read back as a Dart DateTime.
  DateTimeColumn get dueDate => dateTime()();

  TextColumn get category => text()();

  RealColumn get price => real()();

  /// Added in schema version 2 (Step 4).
  ///
  /// SOFT delete flag: "deleting" sets this to true instead of removing the
  /// row. Reads filter it out, so the user sees it gone — but the row stays
  /// in SQLite so the sync engine (Part 4) can later tell the server
  /// "this was deleted". A hard DELETE would leave nothing to sync.
  ///
  /// `withDefault` matters for the migration: existing rows get `false`.
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  /// Tells Drift that `id` is the primary key (instead of an auto-increment).
  @override
  Set<Column> get primaryKey => {id};
}
