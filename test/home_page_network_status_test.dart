import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_info.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_status.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/data/subscription_repository.dart';
import 'package:offline_first_app_flutter_demo/features/subscriptions/presentation/pages/home_page.dart';

import 'helpers/test_database.dart';

/// Lets the test push network statuses manually.
class FakeNetworkInfo implements NetworkInfo {
  final controller = StreamController<NetworkStatus>();

  @override
  Stream<NetworkStatus> watchStatus() => controller.stream;
}

void main() {
  testWidgets('top bar is hidden until status is known, then follows it', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    final networkInfo = FakeNetworkInfo();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          repository: db.subscriptionRepository,
          networkInfo: networkInfo,
        ),
      ),
    );

    // Unknown at startup: nothing shown.
    expect(find.text('Online'), findsNothing);
    expect(find.text('Offline'), findsNothing);

    networkInfo.controller.add(NetworkStatus.online);
    await tester.pump();
    expect(find.text('Online'), findsOneWidget);

    networkInfo.controller.add(NetworkStatus.offline);
    // First pump delivers the stream event, second renders the rebuild.
    await tester.pump();
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Online'), findsNothing);

    await networkInfo.controller.close();
  });
}
