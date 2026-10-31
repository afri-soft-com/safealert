import AVFoundation
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

    // Category only — do NOT setActive(true) here. An active .playback session
    // while the app is backgrounded suppresses APNs alert sounds (banner OK,
    // silence). Activate only when playing an in-app SOS via audioplayers.
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
    } catch {
      NSLog("SafeAlert AVAudioSession: \(error.localizedDescription)")
    }

    // Ensure we can present banners+sound while the app is foregrounded.
    // Firebase swizzling may also set the delegate — calling super keeps both paths.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    application.registerForRemoteNotifications()
    return ok
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    // Free the audio session so the system can play remote-notification sounds.
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
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("SafeAlert APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  /// Foreground: always show banner + play sound for remote AND local alerts.
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
