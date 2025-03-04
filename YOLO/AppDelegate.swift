//  Ultralytics YOLO 🚀 - AGPL-3.0 License
//
//  This file is part of the Ultralytics YOLO app, enabling YOLOv8 model previews on iOS devices.
//  Licensed under AGPL-3.0. For commercial use, refer to Ultralytics licensing: https://ultralytics.com/license
//  Access the source code: https://github.com/ultralytics/yolo-ios-app
//
//  The AppDelegate initializes app settings, manages system-level configurations, and facilitates
//  the integration of additional services such as Firebase analytics.
//  This file includes the app's delegate class, responsible for handling the app's lifecycle events,
//  configuring global settings (such as disabling the idle timer and enabling battery monitoring),
//  and storing app version and device UUID in UserDefaults for easy access throughout the app.
//  An extension to CALayer is also provided to enable easy screenshot functionality for any layer
//  within the app, utilizing the device's screen scale for high-resolution captures.

import UIKit

/// The main application delegate, handling global app behavior and configuration.
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
    var externalWindow: UIWindow?


    @objc func setupExternalDisplay() {
        guard UIScreen.screens.count > 1 else { return }
        let externalScreen = UIScreen.screens.first(where: { $0 != UIScreen.main })!

        print(externalScreen.bounds)
//        let availableModes = externalScreen.availableModes
//
//        guard let highestResolutionMode = availableModes.max(by: { lhs, rhs in
//            lhs.size.width < rhs.size.width
//        }) else {
//            print("利用可能なモードがありません")
//            return
//        }
//
//        // 最高解像度モードを設定（4Kなら3840×2160等）
//        externalScreen.currentMode = highestResolutionMode
//
//        // screen bounds更新
//        let externalScreenBounds = CGRect(x: 0,
//                                          y: 0,
//                                          width: highestResolutionMode.size.width,
//                                          height: highestResolutionMode.size.height)
//
        externalWindow = UIWindow(frame: externalScreen.bounds)
        externalWindow?.screen = externalScreen

        // StoryboardからViewControllerをインスタンス化
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let externalVC = storyboard.instantiateViewController(withIdentifier: "ViewController") as? ViewController else { return }

        externalWindow?.rootViewController = externalVC
        externalWindow?.isHidden = false
    }

    @objc func teardownExternalDisplay() {
        externalWindow?.isHidden = true
        externalWindow = nil
    }
  /// Called when the app finishes launching, used here to set global app settings.
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Disable screen dimming and auto-lock to keep the app active during long operations.
    UIApplication.shared.isIdleTimerDisabled = true

    // Enable battery monitoring to allow the app to adapt its behavior based on battery level.
    UIDevice.current.isBatteryMonitoringEnabled = true

    // Store the app version and build version in UserDefaults for easy access elsewhere in the app.
    if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    {
      UserDefaults.standard.set("\(appVersion) (\(buildVersion))", forKey: "app_version")
    }

    // Store the device's UUID in UserDefaults for identification purposes.
    if let uuid = UIDevice.current.identifierForVendor?.uuidString {
      UserDefaults.standard.set(uuid, forKey: "uuid")
    }

    // Ensure UserDefaults changes are immediately saved.
    UserDefaults.standard.synchronize()
      NotificationCenter.default.addObserver(
          self,
          selector: #selector(setupExternalDisplay),
          name: UIScreen.didConnectNotification,
          object: nil
      )

      NotificationCenter.default.addObserver(
          self,
          selector: #selector(teardownExternalDisplay),
          name: UIScreen.didDisconnectNotification,
          object: nil
      )

      if UIScreen.screens.count > 1 {
          setupExternalDisplay()
      }
    return true
  }
}

/// Extension to CALayer to add functionality for generating screenshots of any layer.
extension CALayer {
  var screenShot: UIImage? {
    // Begin a new image context, using the device's screen scale to ensure high-resolution output.
    UIGraphicsBeginImageContextWithOptions(frame.size, false, UIScreen.main.scale)
    defer {
      UIGraphicsEndImageContext()
    }  // Ensure the image context is cleaned up correctly.

    if let context = UIGraphicsGetCurrentContext() {
      // Render the layer into the current context.
      render(in: context)
      // Attempt to generate an image from the current context.
      return UIGraphicsGetImageFromCurrentImageContext()
    }
    return nil  // Return nil if the operation fails.
  }
}

