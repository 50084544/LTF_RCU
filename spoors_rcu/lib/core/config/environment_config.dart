import 'package:flutter/foundation.dart';

class EnvironmentConfig {
  // SSL Pinning settings
  static bool get enableSslPinning {
    // Read the environment variable set by --dart-define
    const String pinningFlag =
        String.fromEnvironment('SSL_PINNING_ENABLED', defaultValue: 'true');

    // Convert string to bool, defaulting to true for safety
    final bool definedValue = pinningFlag.toLowerCase() == 'true';
    return definedValue;
  }

  // API endpoints
  static const String baseUrl = "https://ltfs--sit.sandbox.my.salesforce.com";

  // Other environment settings
  static const bool enableLogging = kDebugMode;
}
