import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sachet/core/security/ssl_pinning_manager.dart';

/// Security service to protect against various mobile security threats
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  /// Device info plugin for detecting emulators and device properties
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// SSL Pinning manager
  final SSLPinningManager _sslPinningManager = SSLPinningManager();

  bool _isInitialized = false;
  final List<String> _securityIssues = [];

  /// Initialize the security service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize SSL pinning
      await _sslPinningManager.initialize();
      _isInitialized = true;
    } catch (e) {
      debugPrint('Security Service initialization error: $e');
    }
  }

  /// Run all security checks and return true if device is secure
  Future<bool> runSecurityChecks({bool exitOnFailure = true}) async {
    _securityIssues.clear();

    // Run all checks in parallel for faster verification
    final results = await Future.wait([
      //_checkEmulator(),
      _checkRooted(),
      _checkHooking(),
      _checkDebuggerAttached(),
      _checkTampered(),
      _checkDangerousApps(),
      _checkSSLPinning(),
    ]);

    final isSecure = !results.contains(false);

    if (!isSecure && exitOnFailure) {
      _exitApp();
    }

    return isSecure;
  }

  /// Check SSL Pinning integrity
  Future<bool> _checkSSLPinning() async {
    try {
      final isValid = await _sslPinningManager.verifySSLPinning();
      if (!isValid) {
        _securityIssues.add('SSL Pinning verification failed');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('SSL Pinning check error: $e');
      return false;
    }
  }

  /// Get list of detected security issues
  List<String> getSecurityIssues() {
    return List.from(_securityIssues);
  }

  /// Check if running on an emulator
  Future<bool> _checkEmulator() async {
    try {
      // Use multiple methods to detect emulators for better accuracy
      bool isEmulator = false;

      // Use device_info_plus
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        isEmulator = androidInfo.isPhysicalDevice == false ||
            androidInfo.model.toLowerCase().contains('sdk') ||
            androidInfo.model.toLowerCase().contains('emulator') ||
            androidInfo.model.toLowerCase().contains('android sdk') ||
            (androidInfo.manufacturer.toLowerCase().contains('google') &&
                androidInfo.product.toLowerCase().contains('sdk')) ||
            androidInfo.fingerprint.startsWith('generic') ||
            androidInfo.hardware.toLowerCase().contains('goldfish') ||
            androidInfo.hardware.toLowerCase().contains('ranchu');

        if (isEmulator) {
          _securityIssues.add('Device is an emulator');
          return false;
        }
      } else if (Platform.isIOS) {
        // final iosInfo = await _deviceInfo.iosInfo;
        // if (!iosInfo.isPhysicalDevice) {
        //   _securityIssues.add('Device is an iOS simulator');
        //   return false;
        // }
      }

      return true;
    } catch (e) {
      debugPrint('Error checking emulator: $e');
      // In case of error, assume it's not an emulator to avoid blocking legitimate users
      return true;
    }
  }

  /// Check if device is rooted/jailbroken
  Future<bool> _checkRooted() async {
    try {
      bool isRooted = false;

      if (Platform.isAndroid) {
        // Method 1: Check for common SU binaries
        final commonSUPaths = [
          '/system/bin/su',
          '/system/xbin/su',
          '/sbin/su',
          '/system/su',
          '/system/bin/.ext/.su',
          '/system/usr/we-need-root/su',
          '/system/app/Superuser.apk',
          '/data/data/com.noshufou.android.su',
          '/data/data/com.topjohnwu.magisk',
        ];

        // Check if any of these paths exist
        for (final path in commonSUPaths) {
          try {
            final file = File(path);
            if (await file.exists()) {
              isRooted = true;
              break;
            }
          } catch (_) {
            // Ignore file access errors
          }
        }

        // Method 2: Check if build properties have been tampered
        if (!isRooted) {
          try {
            final result = await Process.run('getprop', ['ro.debuggable']);
            final debuggable = result.stdout.toString().trim();
            if (debuggable == '1') {
              isRooted = true;
            }
          } catch (_) {
            // Ignore process errors
          }
        }

        // Method 3: Check for RW system paths
        if (!isRooted) {
          final systemPaths = [
            '/system',
            '/system/bin',
            '/system/sbin',
            '/system/xbin',
            '/vendor/bin',
            '/sbin',
            '/etc',
          ];

          for (final path in systemPaths) {
            try {
              final directory = Directory(path);
              if (await directory.exists()) {
                final testFile = File(
                    '$path/test_rw_${DateTime.now().millisecondsSinceEpoch}');
                await testFile.create();
                await testFile.delete();
                isRooted = true;
                break;
              }
            } catch (_) {
              // Not writable, which is good
            }
          }
        }

        if (isRooted) {
          _securityIssues.add('Device is rooted');
          return false;
        }
      }
      // else if (Platform.isIOS) {
      //   // Check for jailbreak using direct file checks
      //   final jailbreakPaths = [
      //     '/Applications/Cydia.app',
      //     '/Applications/FakeCarrier.app',
      //     '/Applications/Sileo.app',
      //     '/Applications/Zebra.app',
      //     '/bin/bash',
      //     '/usr/sbin/sshd',
      //     '/usr/bin/ssh',
      //     '/etc/apt',
      //     '/private/var/lib/apt',
      //     '/private/var/lib/cydia',
      //     '/private/var/mobile/Library/SBSettings/Themes',
      //   ];

      //   for (final path in jailbreakPaths) {
      //     try {
      //       final file = File(path);
      //       if (await file.exists()) {
      //         isRooted = true;
      //         break;
      //       }
      //     } catch (_) {
      //       // Ignore file access errors
      //     }
      //   }

      //   if (isRooted) {
      //     _securityIssues.add('Device is jailbroken');
      //     return false;
      //   }
      // }

      return true;
    } catch (e) {
      debugPrint('Root detection error: $e');
      // In case of error, assume the device is secure to avoid blocking legitimate users
      return true;
    }
  }

  /// Check for hooking frameworks (Frida, Xposed, Magisk)
  Future<bool> _checkHooking() async {
    try {
      if (Platform.isAndroid) {
        bool isHooked = false;

        // Known hooking frameworks and their artifacts
        final Map<String, List<String>> hookingFrameworks = {
          'Frida': [
            '/data/local/tmp/frida-server',
            '/data/local/tmp/re.frida.server',
            '/system/lib/libfrida-gadget.so',
            '/system/lib64/libfrida-gadget.so',
            '/data/app/io.frida.server',
          ],
          'Xposed': [
            '/system/lib/libxposed_art.so',
            '/system/lib64/libxposed_art.so',
            '/system/framework/XposedBridge.jar',
            '/data/app/de.robv.android.xposed.installer',
            '/data/data/de.robv.android.xposed.installer',
          ],
          'Magisk': [
            '/sbin/magisk',
            '/sbin/.magisk',
            '/data/adb/magisk',
            '/data/magisk',
            '/cache/.disable_magisk',
          ],
          'Objection': [
            '/data/local/tmp/frida-gadget.so',
            '/data/local/tmp/gadget',
          ],
        };

        // Check all paths for each framework
        for (final framework in hookingFrameworks.entries) {
          for (final path in framework.value) {
            try {
              final file = File(path);
              if (await file.exists()) {
                _securityIssues.add('${framework.key} framework detected');
                isHooked = true;
                break;
              }
            } catch (_) {
              // Ignore file access errors
            }
          }
          if (isHooked) break;
        }

        // Check if Frida is listening on its default ports
        if (!isHooked) {
          final fridaPorts = [27042, 27043];
          for (final port in fridaPorts) {
            try {
              final socket = await Socket.connect('localhost', port,
                  timeout: Duration(milliseconds: 300));
              await socket.close();
              _securityIssues.add('Frida server detected on port $port');
              isHooked = true;
              break;
            } catch (_) {
              // No connection means no Frida running on that port, which is good
            }
          }
        }

        // Check for known hooking packages
        if (!isHooked) {
          final hookingPackages = [
            'de.robv.android.xposed.installer',
            'com.saurik.substrate',
            'com.topjohnwu.magisk',
            'io.github.lsposed.manager',
            'org.meowcat.edxposed.manager',
          ];

          try {
            final result = await Process.run('pm', ['list', 'packages']);
            final packages = result.stdout.toString();

            for (final package in hookingPackages) {
              if (packages.contains(package)) {
                _securityIssues.add('Hooking app $package detected');
                isHooked = true;
                break;
              }
            }
          } catch (_) {
            // Ignore process errors
          }
        }

        // Additional Frida detection: check for frida traces in memory
        // This can detect Frida even when it's injected at runtime
        if (!isHooked) {
          try {
            final result =
                await Process.run('grep', ['-l', 'frida', '/proc/self/maps']);
            if (result.stdout.toString().isNotEmpty) {
              _securityIssues.add('Frida detected in memory maps');
              isHooked = true;
            }
          } catch (_) {
            // Ignore process errors
          }
        }

        if (isHooked) {
          return false;
        }
      } else if (Platform.isIOS) {
        bool isHooked = false;

        // Check for Frida, Cydia Substrate, etc.
        final hookingLibraries = [
          '/usr/lib/frida',
          '/usr/lib/FridaGadget.dylib',
          '/usr/lib/libSubstrate.dylib',
          '/usr/lib/substrate',
          '/Library/MobileSubstrate/MobileSubstrate.dylib',
          '/usr/lib/TweakInject',
          '/var/lib/dpkg/info/mobilesubstrate.list',
        ];

        for (final path in hookingLibraries) {
          try {
            final file = File(path);
            if (await file.exists()) {
              _securityIssues.add('iOS hooking library detected: $path');
              isHooked = true;
              break;
            }
          } catch (_) {
            // Ignore file access errors
          }
        }

        if (isHooked) {
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Hooking detection error: $e');
      // In case of error, assume the device is secure to avoid blocking legitimate users
      return true;
    }
  }

  /// Check if debugger is attached
  Future<bool> _checkDebuggerAttached() async {
    try {
      if (Platform.isAndroid) {
        // Check Android debugger
        bool isDebuggable = false;
        bool isDebuggerAttached = false;

        // Check if app is debuggable from build properties
        try {
          final result = await Process.run('getprop', ['ro.debuggable']);
          isDebuggable = result.stdout.toString().trim() == '1';
        } catch (_) {
          // Ignore process errors
        }

        // Check for active debugging through ADB
        try {
          final result = await Process.run('ps', ['-A']);
          isDebuggerAttached =
              result.stdout.toString().contains('android.process.adb');
        } catch (_) {
          // Ignore process errors
        }

        // Another way to check for debugger attachment
        try {
          final file = File('/proc/self/status');
          final contents = await file.readAsString();
          final tracerPidLine = contents.split('\n').firstWhere(
                (line) => line.startsWith('TracerPid:'),
                orElse: () => 'TracerPid: 0',
              );
          final tracerPid =
              int.tryParse(tracerPidLine.split(':')[1].trim()) ?? 0;
          isDebuggerAttached = isDebuggerAttached || tracerPid != 0;
        } catch (_) {
          // Ignore file errors
        }

        if (isDebuggable || isDebuggerAttached) {
          _securityIssues.add('Debugger detected');
          return false;
        }
      } else if (Platform.isIOS) {
        // iOS debugger detection is handled by checking debug symbols
        // but this requires native code through method channels

        // For now, we'll use a basic check for simulator which can't be fully trusted
        // final iosInfo = await _deviceInfo.iosInfo;
        // if (!iosInfo.isPhysicalDevice) {
        //   _securityIssues.add('iOS simulator detected');
        //   return false;
        // }
      }

      return true;
    } catch (e) {
      debugPrint('Debugger detection error: $e');
      // In case of error, assume the device is secure to avoid blocking legitimate users
      return true;
    }
  }

  /// Check for app tampering and integrity
  Future<bool> _checkTampered() async {
    try {
      if (Platform.isAndroid) {
        // Basic approach to detect unofficial app signature
        // This needs to be enhanced with native code for proper signature verification
        try {
          // Get the current package name using environment variables
          // since PackageInfo may not be available
          final packageName =
              'com.ltfinance.spoors_rcu'; // Hard-coded as fallback

          final result = await Process.run('dumpsys', ['package', packageName]);
          final output = result.stdout.toString();

          // Check if the app is debuggable (should not be in production)
          if (output.contains('ApplicationInfo') &&
              output.contains('DEBUGGABLE')) {
            _securityIssues.add('App is debuggable, possible tampering');
            return false;
          }
        } catch (_) {
          // Ignore process errors
        }
      }

      return true;
    } catch (e) {
      debugPrint('App tampering check error: $e');
      // In case of error, assume the device is secure to avoid blocking legitimate users
      return true;
    }
  }

  /// Check for dangerous apps installed on the device
  Future<bool> _checkDangerousApps() async {
    try {
      if (Platform.isAndroid) {
        // List of known dangerous/security testing apps
        final dangerousApps = [
          'com.noshufou.android.su',
          'com.thirdparty.superuser',
          'eu.chainfire.supersu',
          'com.koushikdutta.superuser',
          'com.zachspong.temprootremovejb',
          'com.ramdroid.appquarantine',
          'com.topjohnwu.magisk',
          'com.mwr.dz', // Drozer
          'org.frida.server',
          'org.frida.agent',
          'io.github.veecsh.arnold', // Objection wrapper
          'com.bishopfox.abe', // Android Backup Extractor
          'com.saurik.substrate', // Substrate
          'org.ligi.satoshiproof', // Root checker
          'com.devadvance.rootcloak', // Root cloak
          'de.robv.android.xposed.installer', // Xposed
          'com.formyhm.hideroot', // Hide root
          'com.amphoras.hidemyrootadfree', // Hide root
          'com.saurik.substrate', // Cydia substrate
          'com.android.vending.billing.InAppBillingService.COIN', // Lucky patcher
          'com.chelpus.lackypatch', // Lucky patcher
        ];

        bool hasDangerousApps = false;

        try {
          final result = await Process.run('pm', ['list', 'packages']);
          final installedPackages = result.stdout.toString();

          for (final app in dangerousApps) {
            if (installedPackages.contains(app)) {
              _securityIssues.add('Dangerous app detected: $app');
              hasDangerousApps = true;
              break;
            }
          }
        } catch (_) {
          // Ignore process errors
        }

        if (hasDangerousApps) {
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Dangerous apps check error: $e');
      // In case of error, assume the device is secure to avoid blocking legitimate users
      return true;
    }
  }

  /// Exit the app when security checks fail
  void _exitApp() {
    // Log the security issues before exiting
    debugPrint('Security issues detected: ${_securityIssues.join(', ')}');

    // Force exit the app
    exit(0);
  }

  /// Show security alert dialog
  void showSecurityAlert(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.security, color: Colors.red),
            SizedBox(width: 10),
            Text('Security Alert'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Security threat detected!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'This application cannot run on compromised devices for security reasons.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              exit(0);
            },
            child: Text('Exit'),
          ),
        ],
      ),
    );
  }
}
