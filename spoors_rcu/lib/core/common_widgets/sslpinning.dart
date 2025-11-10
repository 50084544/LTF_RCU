import 'dart:io';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';
import 'package:sachet/core/security/ssl_pinning_manager.dart';
import 'package:sachet/core/security/secure_http_client_adapter.dart';

abstract class CertificateReader {
  static ByteData? cert;
  static ByteData? privateKey;
  static bool _initialized = false;
  // Update to use the Salesforce certificate
  static const String CERTIFICATE_PATH =
      'assets/certificate/login.salesforce.crt';
  // Keep the key path the same if needed
  static const String PRIVATE_KEY_PATH =
      'assets/certificate/wildcard.ltfinance.com.key';

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      cert = await rootBundle.load(CERTIFICATE_PATH);
      // Only load private key if needed for client authentication
      // privateKey = await rootBundle.load(PRIVATE_KEY_PATH);

      _initialized = true;
    } catch (e) {
      throw Exception('Failed to load SSL certificate: $e');
    }
  }

  static ByteData? getCert() {
    return cert;
  }

  static ByteData? getPrivateKey() {
    return privateKey;
  }

  static bool isInitialized() {
    return _initialized;
  }
}

void setupSslPinning(
    bool sslPinningEnabled, dynamic dioClient, dynamic logger) {
  if (sslPinningEnabled) {
    logger.d('Enhanced SSL Pinning Enabled');
    try {
      // Get certificates from SSLPinningManager
      final sslPinningManager = SSLPinningManager();
      final certificates = sslPinningManager.getCertificates();

      if (certificates.isEmpty) {
        logger.e('No certificates available for SSL pinning');
        return;
      }

      // Also include legacy certificate if available
      if (CertificateReader.isInitialized() &&
          CertificateReader.getCert() != null) {
        final legacyCert = CertificateReader.getCert()!;
        if (!certificates.contains(legacyCert)) {
          certificates.add(legacyCert);
        }
      }

      logger
          .d('Setting up SSL pinning with ${certificates.length} certificates');

      // Use the secure HTTP client adapter with our enhanced security
      dioClient.httpClientAdapter = SecureHttpClientAdapter(
        trustedCertificates: certificates,
        allowSelfSigned: false, // Never allow self-signed certificates
        strictHostnameVerification: true, // Always verify hostnames
        allowedHosts: [
          'salesforce.com',
          'api.ltfinance.com',
          'ltfinance.com',
          // Add other trusted domains as needed
        ],
      );

      logger.d('Enhanced SSL Pinning setup completed');
    } on Exception catch (e) {
      logger.e('SSL Pinning setup error: $e');
    }
  } else {
    logger.d('SSL Pinning Disabled');
  }
}
