// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscriptions_dao.dart';

// ignore_for_file: type=lint
mixin _$SubscriptionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SubscriptionsTable get subscriptions => attachedDatabase.subscriptions;
  $SyncMetadataTable get syncMetadata => attachedDatabase.syncMetadata;
  SubscriptionsDaoManager get managers => SubscriptionsDaoManager(this);
}

class SubscriptionsDaoManager {
  final _$SubscriptionsDaoMixin _db;
  SubscriptionsDaoManager(this._db);
  $$SubscriptionsTableTableManager get subscriptions =>
      $$SubscriptionsTableTableManager(_db.attachedDatabase, _db.subscriptions);
  $$SyncMetadataTableTableManager get syncMetadata =>
      $$SyncMetadataTableTableManager(_db.attachedDatabase, _db.syncMetadata);
}
