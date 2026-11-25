import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAppIconChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  /// App icon colour mode (specs/appicon.md "F na iOS"): `sunset` is the primary icon, the other
  /// modes are the alternate icons `AppIcon-<mode>` of the asset catalog. iOS shows its own alert
  /// after a change.
  private static let iconModes = ["day", "night", "sunset", "teal", "japan"]
  private static let iconDefault = "sunset"

  private func registerAppIconChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "metropole/app_icon", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "set" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let mode = call.arguments as? String, AppDelegate.iconModes.contains(mode) else {
        result(FlutterError(code: "unknown_mode", message: "Unknown app icon mode", details: nil))
        return
      }
      let name: String? = mode == AppDelegate.iconDefault ? nil : "AppIcon-\(mode)"
      let app = UIApplication.shared
      if app.alternateIconName == name {
        result(true)
        return
      }
      guard app.supportsAlternateIcons else {
        result(FlutterError(code: "unsupported", message: "Alternate icons are not supported", details: nil))
        return
      }
      app.setAlternateIconName(name) { error in
        // The completion handler may run off the main queue; Flutter results must not.
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "rejected", message: error.localizedDescription, details: nil))
          } else {
            result(true)
          }
        }
      }
    }
  }
}
