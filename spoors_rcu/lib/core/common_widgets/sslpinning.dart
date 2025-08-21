import 'dart:io';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';

abstract class CertificateReader {
  static ByteData? cert;
  static ByteData? privateKey;
  static bool _initialized = false;
  // Update to use the Salesforce certificate
  static const String CERTIFICATE_PATH =
      'assets/certificate/test.salesforce.crt';
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
    logger.d('SSL Pinning Enabled with Salesforce certificate');
    try {
      if (!CertificateReader.isInitialized()) {
        logger.e(
            'Certificate not initialized. Call CertificateReader.initialize() first.');
        return;
      }

      ByteData? bytes = CertificateReader.getCert();
      if (bytes == null) {
        logger.e('Certificate data is null');
        return;
      }

      // Configure Dio SSL Pinning for Salesforce
      (dioClient.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate =
          (HttpClient client) {
        SecurityContext context = SecurityContext();

        try {
          context.setTrustedCertificatesBytes(bytes.buffer.asUint8List());
          logger.d('Successfully set trusted Salesforce certificates');
        } catch (e) {
          logger.e('Failed to set trusted certificates: $e');
        }

        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
          logger.d('Validating certificate for $host:$port');

          // For strict pinning, always return false to reject invalid certs
          return false;
        };

        return client;
      };

      logger.d('Salesforce SSL Pinning setup completed');
    } on Exception catch (e) {
      logger.e('SSL Pinning setup error: $e');
    }
  } else {
    logger.d('SSL Pinning Disabled');
  }
}
