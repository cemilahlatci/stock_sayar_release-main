import Flutter
import UIKit
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let toneChannel = FlutterMethodChannel(
      name: "com.stock_sayar/tone",
      binaryMessenger: controller.binaryMessenger
    )

    toneChannel.setMethodCallHandler { (call, result) in
      if call.method == "playWarningTone" {
        // iOS sistem uyarı sesi (sadece ses, titreşim yok)
        AudioServicesPlaySystemSound(SystemSoundID(1005))
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
