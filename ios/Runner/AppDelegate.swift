import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background sync (workmanager) — NOT yet tested on a real iPhone.
    //
    // 1. Background tasks run in a separate Flutter engine; give it the same
    //    plugins as the app (Drift's file access, Dio, connectivity…).
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // 2. Register the periodic sync with iOS BGTaskScheduler. The identifier
    //    must match BackgroundSyncScheduler.periodicTaskId in Dart and
    //    BGTaskSchedulerPermittedIdentifiers in Info.plist. 30 min is only a
    //    hint: iOS decides when (and whether) to run it.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.example.offline_first_app_flutter_demo.periodicSync",
      earliestBeginInSeconds: NSNumber(value: 30 * 60)
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
