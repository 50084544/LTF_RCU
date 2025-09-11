import 'package:dio/dio.dart';
import 'dart:async';
import 'dart:convert';
import 'package:hive/hive.dart';

/// API service class for handling API communication
class ApiService {
  // Singleton instance
  static final ApiService _instance = ApiService._internal();

  factory ApiService() => _instance;

  late final Dio _dio;
  bool _hasAuthToken = false;

  // Private constructor for singleton
  ApiService._internal() {
    // Initialize Dio with base options
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        contentType: 'application/json',
        responseType: ResponseType.json,
        // headers: {
        //   'X-IBM-Client-Id': '52ce43d0-e5d7-4cc9-90e9-b08ebc98b13a',
        //   'X-IBM-Client-Secret':
        //       'wP4aK7vB3gL8mT3aT1fD4iV4aF1uV6uP8bO3qX4cB5nH5oK0xD'
        // }
      ),
    );

    // Add interceptors for logging
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          return handler.next(options);
        },
        onResponse: (response, handler) {
          return handler.next(response);
        },
        onError: (error, handler) {
          return handler.next(error);
        },
      ),
    );
  }

  /// Login method that handles authentication - making real API call
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      // Create the request payload
      final Map<String, dynamic> payload = {
        "_userName": username,
        "_passWord": password,
      };

      // Make the actual API call
      final response = await _dio.post(
        'https://bmsdev.ltfinance.com/CSM/api/do_LDAP_Authentication',
        data: jsonEncode(payload),
      );

      // Process the response
      if (response.statusCode == 200) {
        final responseData = response.data;
        // Check for successful authentication
        if (responseData['Stts_flg'] == 'S' &&
            responseData['Err_cd'] == '000') {
          // Set auth token flag
          _hasAuthToken = true;
          // final box = await Hive.openBox('auth');
          // await box.put(
          //     'token', DateTime.now().millisecondsSinceEpoch.toString());
          // await box.put('IsLoggedIn', true);
          // await box.put('username', username);
          // Return successful response
          return {
            'success': true,
            'data': {
              'token': DateTime.now().millisecondsSinceEpoch.toString(),
              'user': {
                'username': username,
                'name': 'User',
                'email': '$username@example.com',
              }
            },
            'message': responseData['message'] ?? 'Login successful',
          };
        } else {
          // Authentication failed
          return {
            'success': false,
            'message': responseData['message'] ?? 'Authentication failed',
          };
        }
      } else {
        // HTTP error
        return {
          'success': false,
          'message': 'HTTP Error: ${response.statusCode}',
        };
      }
    } catch (e) {
      // Handle different types of errors
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout) {
          return {
            'success': false,
            'message': 'Connection timeout. Please try again.',
          };
        } else if (e.type == DioExceptionType.receiveTimeout) {
          return {
            'success': false,
            'message':
                'Server is taking too long to respond. Please try again.',
          };
        } else if (e.type == DioExceptionType.connectionError) {
          return {
            'success': false,
            'message': 'No internet connection. Please check your network.',
          };
        }
      }

      // Generic error
      return {
        'success': false,
        'message': 'Login failed: ${e.toString()}',
      };
    }
  }

  /// Set the auth token and store it in Hive
  Future<void> setAuthToken(String token) async {
    try {
      // final box = await Hive.openBox('auth');
      // await box.put('token', token);
      // await box.put('IsLoggedIn', true);

      // Update flag in memory
      _hasAuthToken = true;
    } catch (e) {
      throw Exception('Failed to set authentication token: $e');
    }
  }

  /// Clear the auth token from Hive and memory
  Future<void> clearAuthToken() async {
    try {
      final box = await Hive.openBox('auth');
      await box.delete('token');
      await box.put('IsLoggedIn', false);

      // Update flag in memory
      _hasAuthToken = false;
    } catch (e) {
      throw Exception('Failed to clear authentication token: $e');
    }
  }

  /// Method to check if user is logged in (has valid token)
  bool hasValidToken() {
    return _hasAuthToken;
  }

  /// Get current user profile information - using mock data
  Future<Map<String, dynamic>> getUserProfile() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Return mock user profile data
    return {
      'success': true,
      'data': {
        'id': '12345',
        'username': 'demo_user',
        'name': 'Demo User',
        'email': 'demo@example.com',
        'phone': '+1 123-456-7890',
        'department': 'Finance',
        'role': 'Manager',
        'permissions': ['view_forms', 'edit_forms', 'submit_forms'],
        'preferences': {
          'theme': 'light',
          'notifications': true,
          'dashboard': 'summary'
        }
      },
      'message': 'User profile retrieved successfully',
    };
  }

  /// Check if the current session is valid
  Future<bool> isSessionValid() async {
    try {
      final box = await Hive.openBox('auth');
      final token = box.get('token');
      final isLoggedIn = box.get('IsLoggedIn', defaultValue: false);

      // Basic check - token exists and IsLoggedIn is true
      if (token != null && token.toString().isNotEmpty && isLoggedIn == true) {
        // For a real app: verify token validity with backend
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get the current session information
  Future<Map<String, dynamic>?> getCurrentSession() async {
    try {
      final box = await Hive.openBox('auth');
      final token = box.get('token');
      final username = box.get('username');

      if (token != null && token.toString().isNotEmpty) {
        // Return basic session info from Hive
        return {
          'token': token,
          'user': {
            'username': username ?? '',
          }
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
