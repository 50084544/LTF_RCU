import 'dart:io';
import 'package:BMS/core/common_widgets/sslpinning.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

/// Enhanced SSL Pinning Manager to protect against certificate tampering
/// and advanced bypassing techniques like Frida and objection scripts
class SSLPinningManager {
  static final SSLPinningManager _instance = SSLPinningManager._internal();
  factory SSLPinningManager() => _instance;
  SSLPinningManager._internal();

  bool _isInitialized = false;

  // Certificate paths for multiple certificates (primary + backup)
  static const List<String> _certificatePaths = [
    'assets/certificate/test.salesforce.crt', // Primary certificate
    'assets/certificate/wildcard.ltfinance.com.pem', // Backup certificate
  ];

  // Store loaded certificates
  final List<ByteData> _certificates = [];

  // For detecting tampering
  final MethodChannel _securityChannel =
      const MethodChannel('com.spoors.rcu/security');

  // Detection flags
  bool _isHooked = false;
  bool _isDebugged = false;
  DateTime? _lastCheckedTime;

  /// Initialize SSL pinning with multiple certificates
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Load all certificates
      for (final path in _certificatePaths) {
        try {
          final cert = await rootBundle.load(path);
          _certificates.add(cert);
          debugPrint('Loaded certificate: $path');
        } catch (e) {
          debugPrint('Failed to load certificate $path: $e');
          // Continue loading other certificates even if one fails
        }
      }

      // If no certificates could be loaded, initialization failed
      if (_certificates.isEmpty) {
        debugPrint(
            'SSL Pinning initialization failed: No certificates could be loaded');
        return false;
      }

      // Initialize the legacy certificate reader for backward compatibility
      await CertificateReader.initialize();

      // Check for hooking frameworks
      await _detectHooking();

      // Set up periodic security checks
      _setupPeriodicChecks();

      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('SSL Pinning initialization error: $e');
      return false;
    }
  }

  /// Set up periodic security checks
  void _setupPeriodicChecks() {
    // Check for security violations every 30 seconds
    Timer.periodic(const Duration(seconds: 30), (_) {
      _detectHooking();
      _detectDebugging();
    });
  }

  /// Detect hooking frameworks like Frida, Xposed, Substrate
  Future<bool> _detectHooking() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final result =
            await _securityChannel.invokeMethod<bool>('checkHooking') ?? false;
        _isHooked = result;
        if (_isHooked) {
          debugPrint('WARNING: Hooking framework detected!');
        }
        return _isHooked;
      }
    } catch (e) {
      debugPrint('Error checking for hooking frameworks: $e');
    }
    return false;
  }

  /// Detect if a debugger is attached
  Future<bool> _detectDebugging() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final result =
            await _securityChannel.invokeMethod<bool>('checkDebugging') ??
                false;
        _isDebugged = result;
        if (_isDebugged) {
          debugPrint('WARNING: Debugger detected!');
        }
        return _isDebugged;
      }
    } catch (e) {
      debugPrint('Error checking for debugger: $e');
    }
    return false;
  }

  /// Check for time manipulation (anti-replay attacks)
  bool _checkTimeManipulation() {
    final now = DateTime.now();
    if (_lastCheckedTime != null) {
      // If current time is before last check time, time was manipulated
      if (now.isBefore(_lastCheckedTime!)) {
        debugPrint('WARNING: Time manipulation detected!');
        return true;
      }

      // If time difference is too large, something might be wrong
      if (now.difference(_lastCheckedTime!).inMinutes > 5) {
        debugPrint('WARNING: Unusual time gap detected!');
      }
    }
    _lastCheckedTime = now;
    return false;
  }

  /// Verify SSL pinning configuration with enhanced security
  Future<bool> verifySSLPinning() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Security checks
    final isHooked = await _detectHooking();
    final isDebugged = await _detectDebugging();
    final isTimeManipulated = _checkTimeManipulation();

    // Fail if any security check fails
    if (isHooked || isDebugged || isTimeManipulated) {
      debugPrint('SSL Pinning verification failed: Security check failed');
      return false;
    }

    // Check if certificates are loaded properly
    if (_certificates.isEmpty) {
      debugPrint('SSL Pinning verification failed: No certificates loaded');
      return false;
    }

    // Also check legacy certificate
    if (!CertificateReader.isInitialized() ||
        CertificateReader.getCert() == null) {
      debugPrint(
          'SSL Pinning verification failed: Legacy certificate not loaded');
      // Don't return false here, as we have our new certificates
    }

    return true;
  }

  /// Get the list of loaded certificates
  List<ByteData> getCertificates() {
    return List.from(_certificates);
  }

  /// Check if any security issues are detected
  bool hasSecurityIssues() {
    return _isHooked || _isDebugged;
  }
}
