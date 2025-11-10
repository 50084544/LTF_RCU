import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sachet/core/security/ssl_pinning_manager.dart';

/// Custom interceptor to validate certificates and detect tampering attempts at the network layer
class SecurityInterceptor extends Interceptor {
  /// Called before request is sent
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Check security before allowing the request
    if (_checkSecurityBeforeRequest()) {
      super.onRequest(options, handler);
    } else {
      // Fail the request if security checks fail
      handler.reject(
        DioException(
          requestOptions: options,
          error: 'Security verification failed. Request blocked.',
          type: DioExceptionType.badResponse,
        ),
      );
    }
  }

  /// Called when response is received
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Verify the response integrity
    if (_verifyResponseIntegrity(response)) {
      super.onResponse(response, handler);
    } else {
      // Reject the response if it fails integrity checks
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          error:
              'Response integrity check failed. Possible tampering detected.',
          type: DioExceptionType.badResponse,
          response: response,
        ),
      );
    }
  }

  /// Called when an error occurs
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Check if the error is related to SSL issues
    if (_isSslError(err)) {
      debugPrint('SSL Error detected: ${err.message}');

      // Replace with a more generic error to avoid leaking information
      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error:
              'Secure connection failed. Please check your network settings.',
          type: DioExceptionType.badResponse,
        ),
      );
    } else {
      super.onError(err, handler);
    }
  }

  /// Check security before making a request
  bool _checkSecurityBeforeRequest() {
    try {
      // Get the SSL pinning manager instance
      final sslPinningManager = SSLPinningManager();

      // Check if there are any security issues
      if (sslPinningManager.hasSecurityIssues()) {
        debugPrint('Security issues detected. Blocking request.');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error during security check: $e');
      // Fail closed (secure by default)
      return false;
    }
  }

  /// Verify the integrity of the response
  bool _verifyResponseIntegrity(Response response) {
    try {
      // Check for suspicious response headers or content
      final headers = response.headers.map;

      // Look for signs of proxy or MITM attacks
      if (headers.containsKey('via') ||
          headers.containsKey('x-forwarded-for') ||
          headers.containsKey('x-proxy-id')) {
        debugPrint('Suspicious proxy headers detected in response');
        return false;
      }

      // Additional integrity checks can be added here

      return true;
    } catch (e) {
      debugPrint('Error during response integrity verification: $e');
      // Fail closed (secure by default)
      return false;
    }
  }

  /// Check if an error is related to SSL
  bool _isSslError(DioException err) {
    return err.error is HandshakeException ||
        err.error is TlsException ||
        err.error is CertificateException ||
        (err.error is SocketException &&
            (err.error.toString().contains('SSL') ||
                err.error.toString().contains('certificate') ||
                err.error.toString().contains('handshake')));
  }
}

// No additional imports needed, all included at the top
