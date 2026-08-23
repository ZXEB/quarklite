import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        UNUserNotificationCenter.current().delegate = self
        // iOS parallel downloader channel (manual, no pod)
        // Register after engine is ready
        if let engine = self.window?.rootViewController as? FlutterViewController {
            IosParallelPlugin.registerManually(messenger: engine.binaryMessenger)
        } else if let messenger = self.engine?.binaryMessenger {
            IosParallelPlugin.registerManually(messenger: messenger)
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
