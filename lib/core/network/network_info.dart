import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:offline_first_app_flutter_demo/core/network/network_status.dart';

// ---------------------------------------------------------------------------
// Network Info
// ---------------------------------------------------------------------------

/// Watches whether the device has real internet access.
///
/// - [Connectivity] reacts instantly to Wi-Fi / mobile data being toggled.
///   Losing every interface means offline right away.
/// - [InternetConnection] confirms a network actually reaches the internet
///   (e.g. not a captive portal) and re-checks periodically, catching drops
///   while Wi-Fi itself stays connected.
class NetworkInfo {
  NetworkInfo({
    Connectivity? connectivity,
    InternetConnection? internetConnection,
  }) : _connectivity = connectivity ?? Connectivity(),
       _internetConnection = internetConnection ?? InternetConnection();

  final Connectivity _connectivity;
  final InternetConnection _internetConnection;

  /// Emits the current status once known, then only when it changes.
  Stream<NetworkStatus> watchStatus() {
    late final StreamController<NetworkStatus> controller;
    StreamSubscription<List<ConnectivityResult>>? connectivitySub;
    StreamSubscription<InternetStatus>? internetSub;
    NetworkStatus? lastStatus;

    // Incremented on every connectivity change so a slow internet check
    // started earlier cannot overwrite a newer result.
    var checkId = 0;

    void emit(NetworkStatus status) {
      if (controller.isClosed || status == lastStatus) return;
      lastStatus = status;
      controller.add(status);
    }

    Future<void> verifyInternet() async {
      final id = ++checkId;
      final hasInternet = await _internetConnection.hasInternetAccess;
      if (id != checkId) return;
      emit(hasInternet ? NetworkStatus.online : NetworkStatus.offline);
    }

    void onConnectivityChanged(List<ConnectivityResult> results) {
      final noInterface = results.every((r) => r == ConnectivityResult.none);
      if (noInterface) {
        checkId++; // Cancel any in-flight internet check.
        emit(NetworkStatus.offline);
      } else {
        verifyInternet();
      }
    }

    controller = StreamController<NetworkStatus>(
      onListen: () {
        connectivitySub = _connectivity.onConnectivityChanged.listen(
          onConnectivityChanged,
        );
        internetSub = _internetConnection.onStatusChange.listen(
          (status) => emit(
            status == InternetStatus.connected
                ? NetworkStatus.online
                : NetworkStatus.offline,
          ),
        );
        verifyInternet();
      },
      onCancel: () async {
        await connectivitySub?.cancel();
        await internetSub?.cancel();
      },
    );

    return controller.stream;
  }
}
