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
        let ret = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        // Setup range manager after super has created window
        if let controller = window?.rootViewController as? FlutterViewController {
            IosRangeDownloadManager.shared.setup(with: controller)
        } else {
            // Fallback: search windows
            DispatchQueue.main.async {
                if let ctrl = UIApplication.shared.windows.first?.rootViewController as? FlutterViewController {
                    IosRangeDownloadManager.shared.setup(with: ctrl)
                } else if let delegate = UIApplication.shared.delegate as? FlutterAppDelegate,
                          let win = delegate.window,
                          let ctrl2 = win.rootViewController as? FlutterViewController {
                    IosRangeDownloadManager.shared.setup(with: ctrl2)
                }
            }
        }
        return ret
    }

    override func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
