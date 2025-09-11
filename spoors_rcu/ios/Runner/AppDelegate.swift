import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register security check plugin
    let controller = window.rootViewController as! FlutterViewController
    let securityChannel = FlutterMethodChannel(
      name: "com.spoors.rcu/security",
      binaryMessenger: controller.binaryMessenger)
    
    let securityPlugin = SecurityCheckPlugin()
    securityChannel.setMethodCallHandler(securityPlugin.handle)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
