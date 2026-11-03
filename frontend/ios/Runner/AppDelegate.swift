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

    // Before super.application: Dart starts during that call and must already
    // be able to read the saved login.
    registerSessionStore()
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if sessionChannel == nil {
      registerSessionStore()
    }
    application.registerForRemoteNotifications()
    return ok
  }

  /// Login session, read with string(forKey:) — the same store that already
  /// keeps the APNs token after iOS kills the app. SharedPreferences' getAll
  /// does not.
  private var sessionChannel: FlutterMethodChannel?
  private static let sessionKey = "safealert.session.v1"

  private func registerSessionStore() {
    guard let registrar = self.registrar(forPlugin: "SafeAlertSession") else {
      NSLog("SafeAlert session store: registrar missing")
      return
    }
    let channel = FlutterMethodChannel(
      name: "safealert/session",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      let defaults = UserDefaults.standard
      switch call.method {
      case "read":
        result(defaults.string(forKey: AppDelegate.sessionKey))
      case "write":
        if let raw = call.arguments as? String {
          defaults.set(raw, forKey: AppDelegate.sessionKey)
          defaults.synchronize()
          result(true)
        } else {
          result(false)
        }
      case "clear":
        defaults.removeObject(forKey: AppDelegate.sessionKey)
        defaults.synchronize()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    sessionChannel = channel
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    UserDefaults.standard.synchronize()
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
