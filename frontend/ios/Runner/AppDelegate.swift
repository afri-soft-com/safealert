import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Mirrored into UserDefaults for Flutter SharedPreferences (`flutter.` prefix).
  private static let apnsPrefsKey = "flutter.safealert_apns_device_token"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Category only — do NOT setActive(true) here. An active .playback session
    // while the app is backgrounded suppresses APNs alert sounds.
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
    } catch {
      NSLog("SafeAlert AVAudioSession: \(error.localizedDescription)")
    }

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    application.registerForRemoteNotifications()
    return ok
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    do {
      try AVAudioSession.sharedInstance().setActive(
        false,
        options: [.notifyOthersOnDeactivation]
      )
    } catch {
      NSLog("SafeAlert AVAudioSession deactivate: \(error.localizedDescription)")
    }
    super.applicationDidEnterBackground(application)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Hex token for direct APNs (FCM Console APNs key is invalid — iOS killed
    // push must use our server APNS_* path with this native token).
    let hex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    UserDefaults.standard.set(hex, forKey: AppDelegate.apnsPrefsKey)
    NSLog("SafeAlert APNs device token ready (\(hex.count) hex chars)")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("SafeAlert APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}
