import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // FirebaseAppDelegateProxyEnabled=true: FlutterAppDelegate + Firebase swizzling
    // own UNUserNotificationCenter and APNs token forwarding. Just ensure we request
    // remote registration so a killed app can still receive alert pushes via APNs.
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    application.registerForRemoteNotifications()
    return ok
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("SafeAlert APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
