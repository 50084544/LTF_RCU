import 'dart:io';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:sachet/core/common_widgets/sslpinning.dart';

/// Utility class for certificate validation and fingerprint generation
class CertificateValidator {
  // Known fingerprints for your domains (fill these in with actual values)
  static const Map<String, String> _trustedFingerprints = {
    'ltfs--sit.sandbox.my.salesforce.com': '', // Add actual fingerprint here
    // Add more domains if needed
  };

  /// Validates a host's SSL certificate against the stored fingerprint
  static Future<bool> validateHost(String host) async {
    try {
      // Get the trusted certificate
      if (!CertificateReader.isInitialized()) {
        await CertificateReader.initialize();
      }

      // Connect to the host and get its certificate
      final socket = await SecureSocket.connect(
        host,
        443,
        onBadCertificate: (_) => true, // Temporarily accept to examine
      );

      // Get server's certificate
      final cert = socket.peerCertificate;
      await socket.close();

      if (cert == null) {
        return false;
      }

      // Calculate fingerprint of the received certificate
      final serverFingerprint = _calculateFingerprint(cert.der);

      // Compare with our trusted fingerprint
      final trustedFingerprint = _trustedFingerprints[host];
      if (trustedFingerprint == null || trustedFingerprint.isEmpty) {
        return false;
      }

      final isValid = serverFingerprint == trustedFingerprint;
      return isValid;
    } catch (e) {
      return false;
    }
  }

  /// Calculates SHA-256 fingerprint from certificate bytes
  static String _calculateFingerprint(List<int> certBytes) {
    final digest = sha256.convert(certBytes);
    return digest.toString();
  }

  /// Utility method to get fingerprint of bundled certificate
  static Future<String> getBundledCertificateFingerprint() async {
    if (!CertificateReader.isInitialized()) {
      await CertificateReader.initialize();
    }

    final certBytes = CertificateReader.getCert()?.buffer.asUint8List();
    if (certBytes == null) {
      return '';
    }

    final digest = sha256.convert(certBytes);
    return digest.toString();
  }

  /// Gets the fingerprint of a remote server certificate for configuration
  /// Use this to get the fingerprints to add to _trustedFingerprints
  static Future<String> printRemoteCertificateFingerprint(String host) async {
    try {
      final socket = await SecureSocket.connect(
        host,
        443,
        onBadCertificate: (_) => true,
      );

      final cert = socket.peerCertificate;
      await socket.close();

      if (cert == null) {
        return '';
      }

      final fingerprint = _calculateFingerprint(cert.der);
      return fingerprint;
    } catch (e) {
      return '';
    }
  }
}
