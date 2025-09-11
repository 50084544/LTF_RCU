import 'package:BMS/core/security/security_service.dart';
import 'package:flutter/material.dart';

/// A utility class to allow easy security checks from anywhere in the app
class AppSecurity {
  /// Singleton instance
  static final AppSecurity _instance = AppSecurity._internal();
  factory AppSecurity() => _instance;
  AppSecurity._internal();

  /// The security service instance
  final SecurityService _securityService = SecurityService();

  /// Initialize security
  Future<void> initialize() async {
    await _securityService.initialize();
  }

  /// Run security checks
  Future<bool> verify({bool exitOnFailure = true}) async {
    return await _securityService.runSecurityChecks(
        exitOnFailure: exitOnFailure);
  }

  /// Show security alert dialog
  void showSecurityAlert(BuildContext context) {
    _securityService.showSecurityAlert(context);
  }

  /// Get list of detected security issues
  List<String> getSecurityIssues() {
    return _securityService.getSecurityIssues();
  }
}
