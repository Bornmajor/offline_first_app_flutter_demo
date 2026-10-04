import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/database/app_database.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_info.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_status.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/pages/home_page.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/widgets/subscription_card.dart';

import 'helpers/test_database.dart';

/// Network never reports, so the test focuses on the list only.
class _SilentNetworkInfo implements NetworkInfo {
  @override
  Stream<NetworkStatus> watchStatus() => const Stream.empty();
}

void main() {
  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          repository: db.subscriptionRepository,
          networkInfo: _SilentNetworkInfo(),
        ),
      ),
    );
    // Let the first Drift emission arrive and render.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the empty state when the table is empty', (tester) async {
    await pumpHome(tester);

    expect(find.textContaining('No subscriptions yet'), findsOneWidget);
    expect(find.byType(SubscriptionCard), findsNothing);
  });

  testWidgets('shows rows from the database and updates live', (tester) async {
    await pumpHome(tester);
    expect(find.byType(SubscriptionCard), findsNothing);

    // Write straight to the database — no "refresh" call on the page.
    await tester.runAsync(
      () => insertTestSubscription(
        db,
        name: 'Netflix',
        dueDate: DateTime.now().add(const Duration(days: 10)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(SubscriptionCard), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
  });

  group('delete from the card', () {
    Future<void> pumpHomeWithNetflix(WidgetTester tester) async {
      await tester.runAsync(
        () => insertTestSubscription(
          db,
          name: 'Netflix',
          dueDate: DateTime.now().add(const Duration(days: 10)),
        ),
      );
      await pumpHome(tester);
      expect(find.byType(SubscriptionCard), findsOneWidget);

      // Tap the card's Delete button → confirmation dialog.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Netflix?'), findsOneWidget);
    }

    testWidgets('Cancel keeps the subscription', (tester) async {
      await pumpHomeWithNetflix(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(SubscriptionCard), findsOneWidget);
      final row = (await db.select(db.subscriptions).get()).single;
      expect(row.isDeleted, isFalse);
    });

    testWidgets('confirming removes the card and soft-deletes the row', (
      tester,
    ) async {
      await pumpHomeWithNetflix(tester);

      // Two "Delete" texts now: the card's button and the dialog's. The
      // dialog is on top, so it's the last one.
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.byType(SubscriptionCard), findsNothing);
      expect(find.textContaining('No subscriptions yet'), findsOneWidget);

      final row = (await db.select(db.subscriptions).get()).single;
      expect(row.isDeleted, isTrue);
    });
  });
}
