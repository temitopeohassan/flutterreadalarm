import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Before launch finishes, so the tap on an alarm that opened the app
    // reaches the alarm engine.
    AlarmEngine.shared.attach()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Reading alarms (AlarmEngine.swift), after the plugins.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReadAlarmEngine") {
      AlarmEngine.register(with: registrar)
    }
  }
}
