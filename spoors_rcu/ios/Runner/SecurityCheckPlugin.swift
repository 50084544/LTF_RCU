import Flutter
import UIKit

@objc public class SecurityCheckPlugin: NSObject, FlutterPlugin {
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.spoors.rcu/security", binaryMessenger: registrar.messenger())
        let instance = SecurityCheckPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkJailbreak":
            result(checkJailbreak())
        case "checkHooking":  // Match the method name used in Dart code
            result(checkIosHooking())
        case "checkDebugging":  // Match the method name used in Dart code
            result(checkDebugger())
        case "isDebuggerAttached":
            result(checkDebugger())
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func checkJailbreak() -> Bool {
        // Check for common jailbreak files
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Applications/FakeCarrier.app",
            "/Applications/Icy.app",
            "/Applications/IntelliScreen.app",
            "/Applications/MxTube.app",
            "/Applications/RockApp.app",
            "/Applications/SBSettings.app",
            "/Applications/Sileo.app",
            "/Applications/WinterBoard.app",
            "/bin/bash",
            "/bin/sh",
            "/etc/apt",
            "/etc/ssh/sshd_config",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/private/var/stash",
            "/usr/bin/sshd",
            "/usr/libexec/sftp-server",
            "/usr/sbin/sshd"
        ]
        
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // Check if the app can write to locations that it shouldn't be able to
        let restrictedPath = "/private/jailbreak_test.txt"
        do {
            try "test".write(toFile: restrictedPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: restrictedPath)
            return true
        } catch {
            // Expected behavior - can't write to restricted path
        }
        
        // Check if cydia URL scheme is openable
        if let url = URL(string: "cydia://package/com.example.package"), UIApplication.shared.canOpenURL(url) {
            return true
        }
        
        return false
    }
    
    private func checkIosHooking() -> Bool {
        // Check for Frida, Cydia Substrate, etc.
        let hookingLibraries = [
            "/usr/lib/frida",
            "/usr/lib/FridaGadget.dylib",
            "/usr/lib/libSubstrate.dylib",
            "/usr/lib/substrate",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/Library/MobileSubstrate/DynamicLibraries",
            "/Library/Frameworks/CydiaSubstrate.framework"
        ]
        
        for path in hookingLibraries {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // Check for suspicious environment variables
        let suspiciousEnvVars = ["DYLD_INSERT_LIBRARIES", "OBJC_DISABLE_GC"]
        for var in suspiciousEnvVars {
            if ProcessInfo.processInfo.environment[var] != nil {
                return true
            }
        }
        
        return false
    }
    
    private func checkDebugger() -> Bool {
        #if DEBUG
            return true
        #else
            // Check if debugger is attached using sysctl
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            
            let sysctlResult = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
            
            if sysctlResult == 0 {
                // The P_TRACED flag is set if a debugger is attached
                return (info.kp_proc.p_flag & P_TRACED) != 0
            }
            return false
        #endif
    }
}
