import 'package:BMS/core/network/LocalJsonStorage.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:async';
import 'dart:convert';
import 'package:hive/hive.dart';
import '../../core/config/environment_config.dart';
import 'package:BMS/core/common_widgets/sslpinning.dart';
import 'package:flutter/foundation.dart';
import 'package:BMS/core/security/security_service.dart';

class ApiCall {
  static final ApiCall _instance = ApiCall._internal();
  factory ApiCall() => _instance;
  late final Dio _dio;
  bool _sslPinningInitialized = false;

  ApiCall._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: EnvironmentConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );

    // Initialize SSL Pinning right away
    _initSslPinning();
  }

  // Method to initialize SSL Pinning
  Future<void> _initSslPinning() async {
    try {
      // Verify security checks before initializing SSL pinning
      // This adds an additional layer of protection before API calls
      final securityService = SecurityService();
      await securityService.initialize();
      await securityService.runSecurityChecks();

      // Initialize certificate reading
      await CertificateReader.initialize();

      // Setup SSL Pinning on the Dio instance
      final bool enableSslPinning = EnvironmentConfig.enableSslPinning;

      setupSslPinning(enableSslPinning, _dio, _CustomLogger());

      _sslPinningInitialized = true;
    } catch (e) {
      // Fallback to no SSL Pinning in case of error
      _sslPinningInitialized = false;
    }
  }

  // Ensure SSL Pinning is initialized before making API calls
  Future<void> _ensureSslPinningInitialized() async {
    if (!_sslPinningInitialized) {
      await _initSslPinning();
    }
  }

  // Get authentication token and then fetch record data
  Future<Map<String, dynamic>> callApi({
    String endpoint = 'default',
    String? title,
    Map<String, dynamic>? data,
    String? username,
    String? objectType,
    String? code,
    String? workId,
    List<Map<String, dynamic>>? imageFiles,
  }) async {
    // Ensure SSL Pinning is initialized
    await _ensureSslPinningInitialized();
    try {
      // First get authentication token
      final authResult = await _getAuthToken();

      if (!authResult['success']) {
        return authResult; // Return error from authentication
      }

      switch (endpoint.toLowerCase()) {
        case 'listview':
          final recordsResult = await callTokenApi(username: username);
          return recordsResult;

        case 'schema':
          final schemaResult = await callSchemaApi(recordType: title);
          return schemaResult;

        case 'submit':
          final submitResult = await callSubmitApi(data: data);
          return submitResult;

        case 'reference':
          final referenceresult =
              await callReferenceApi(objectType: objectType, code: code);
          return referenceresult;

        case 'uploadimages':
          if (workId == null || imageFiles == null || imageFiles.isEmpty) {
            return {
              'success': false,
              'message': 'Missing workId or imageFiles for image upload'
            };
          }
          final uploadResult = await callImageApi(
            workId: workId,
            imageFiles: imageFiles,
          );
          return uploadResult;

        default:
          return {'success': false, 'message': 'Invalid endpoint specified'};
      }
      // Now that we have the token, call the second API to get record data
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> _getAuthToken() async {
    // Ensure SSL Pinning is initialized
    await _ensureSslPinningInitialized();

    try {
      final payload = {
        "client_id":
            "3MVG9pcaEGrGRoTIJAfV6nezKhM20xn.GHZekaOsVQ_.brE.6VPTyMuxaAhU2FnQYeNLtdfplfpq6F0QPxmcd",
        "client_secret":
            "1C970FF68250B704F8C4D955FA83F2BC67DDF899EDA4D8A6F35277690E007A54",
        "username": "Aman.raj@techilaservices.com.sit ",
        "grant_type": "password",
        "password": "Passion@1",
      };

      final response = await _dio.post(
        'https://test.salesforce.com/services/oauth2/token',
        data: payload,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      if (response.statusCode == 200) {
        // Make sure response.data is a Map and not trying to convert to string
        if (response.data is Map) {
          return {
            'success': true,
            'data': response.data,
            'message': 'Authentication successful'
          };
        } else if (response.data is String) {
          try {
            final decodedData = json.decode(response.data);
            return {
              'success': true,
              'data': decodedData,
              'message': 'Authentication successful'
            };
          } catch (e) {
            return {
              'success': false,
              'message': 'JSON Parsing Error: ${e.toString()}'
            };
          }
        } else {
          return {'success': false, 'message': 'Unexpected response format'};
        }
      } else if (response.statusCode == 404) {
        return {'success': false, 'message': 'No records found'};
      } else {
        return {'success': false, 'message': 'No Records Found'};
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 404) {
        return {'success': false, 'message': 'No records found'};
      } else {
        return {
          'success': false,
          'message': 'Something went wrong in ListView'
        };
      }
    }
  }

  Future<Map<String, dynamic>> callSchemaApi({String? recordType}) async {
    // Ensure SSL Pinning is initialized
    await _ensureSslPinningInitialized();

    try {
      // First get authentication token
      final authResult = await _getAuthToken();
      if (!authResult['success']) {
        return authResult; // Return error if authentication failed
      }

      final accessToken = authResult['data']['access_token'];

      // Make sure the accessToken is a String
      if (accessToken == null || !(accessToken is String)) {
        return {'success': false, 'message': 'Invalid access token format'};
      }

      // Store the token in Hive for future use
      // final box = await Hive.openBox('token_data');
      // await box.put('access_token', accessToken);

      // Replace spaces with underscores in recordType
      String formattedRecordType;
      if (recordType == 'FMR_4_theft_&_robbery') {
        formattedRecordType = 'FMR_4_theft_robbery';
      } else {
        formattedRecordType =
            recordType != null ? recordType.replaceAll(' ', '_') : "default";
      }
      final payload = {
        "recordType": formattedRecordType,
      };

      final schemaBox = await Hive.openBox('schema');
      // Store the record type to track which schema we're currently using
      await schemaBox.put('current_record_type', formattedRecordType);
      // Either clear the schema completely or at least the specific schema for this record type
      if (schemaBox.containsKey('schema')) {
        await schemaBox.delete('schema');
      }

      final response = await _dio.post(
        'https://ltfs--sit.sandbox.my.salesforce.com/services/apexrest/rcu/schema',
        data:
            json.encode(payload), // Ensure payload is properly encoded as JSON
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        // Store the raw response data in Hive
        await Hive.openBox('schema').then((box) {
          box.put('schema', response.data);
        });

        // Save response to JSON file properly handling different types
        try {
          await LocalJsonStorage.saveResponse('schema', response.data);
        } catch (e) {
          // Continue execution even if JSON storage fails
        }

        // Handle different response types
        if (response.data is Map) {
          return {
            'success': true,
            'data': response.data,
            'message': 'Records fetched successfully'
          };
        } else if (response.data is List) {
          // Handle List<dynamic> response type
          return {
            'success': true,
            'data': {'records': response.data},
            'message': 'Records fetched successfully'
          };
        } else if (response.data is String) {
          try {
            final decodedData = json.decode(response.data);
            return {
              'success': true,
              'data': decodedData,
              'message': 'Records fetched successfully'
            };
          } catch (e) {
            return {
              'success': false,
              'message': 'JSON Parsing Error: ${e.toString()}'
            };
          }
        } else {
          return {
            'success': false,
            'message':
                'Unexpected response format: ${response.data.runtimeType}'
          };
        }
      } else if (response.statusCode == 404) {
        return {'success': false, 'message': 'No records found'};
      } else {
        return {'success': false, 'message': 'No Records Found'};
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 404) {
        return {'success': false, 'message': 'No records found'};
      } else {
        return {
          'success': false,
          'message': 'Something went wrong in ListView'
        };
      }
    }
  }

  Future<Map<String, dynamic>> callSubmitApi(
      {Map<String, dynamic>? data}) async {
    try {
      // First get authentication token
      final authResult = await _getAuthToken();
      if (!authResult['success']) {
        return authResult; // Return error if authentication failed
      }

      final accessToken = authResult['data']['access_token'];

      // Process fieldValues to handle booleans properly
      if (data != null && data.containsKey('fieldValues')) {
        // Create a new Map<String, dynamic> to ensure proper typing
        final Map<String, dynamic> fieldValues =
            Map<String, dynamic>.from(data['fieldValues']);
        data['fieldValues'] = fieldValues;

        // Process each field for potential boolean conversion
        fieldValues.forEach((key, value) {
          if (value is String) {
            if (value.toLowerCase() == 'true') {
              fieldValues[key] = true;
            } else if (value.toLowerCase() == 'false') {
              fieldValues[key] = false;
            }
          }
        });
      }

      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      String prettyJson = encoder.convert(data);
      print('Image upload payload:');
      prettyJson.split('\n').forEach((line) => print(line));

      final response = await _dio.post(
        'https://ltfs--sit.sandbox.my.salesforce.com/services/apexrest/rcu/record',
        data: data != null ? jsonEncode(data) : null,
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        // Create a properly typed response map
        Map<String, dynamic> result = {};

        // Handle different response types
        if (response.data is Map) {
          // Safely convert any Map to Map<String, dynamic>
          result = Map<String, dynamic>.from(response.data);
        } else if (response.data is String) {
          try {
            // Try to decode the string as JSON
            final decodedData = json.decode(response.data);
            if (decodedData is Map) {
              result = Map<String, dynamic>.from(decodedData);
            } else {
              result = {'message': response.data};
            }
          } catch (e) {
            // If it's not valid JSON, just store it as a message
            result = {'message': response.data};
          }
        } else {
          // For any other type, convert to string
          result = {'message': response.data.toString()};
        }

        // Add success flag
        result['success'] = true;
        return result;
      } else if (response.statusCode == 404) {
        return {'success': false, 'message': 'No records found'};
      } else {
        return {'success': false, 'message': 'No Records Found'};
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 404) {
        return {'success': false, 'message': 'No records found'};
      } else {
        return {
          'success': false,
          'message': 'Something went wrong in ListView'
        };
      }
    }
  }

  Future<Map<String, dynamic>> callReferenceApi(
      {String? objectType, String? code}) async {
    try {
      // First get authentication token
      final authResult = await _getAuthToken();
      if (!authResult['success']) {
        return authResult; // Return error if authentication failed
      }

      final accessToken = authResult['data']['access_token'];

      // Make sure the accessToken is a String
      if (accessToken == null || !(accessToken is String)) {
        return {'success': false, 'message': 'Invalid access token format'};
      }

      // Store the token in Hive for future use
      // final box = await Hive.openBox('token_data');
      // await box.put('access_token', accessToken);

      final payload = {
        "objectType": objectType,
        "code": code,
      };

      final response = await _dio.post(
        'https://ltfs--sit.sandbox.my.salesforce.com/services/apexrest/rcu/fetchCode',
        data:
            json.encode(payload), // Ensure payload is properly encoded as JSON
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        // Process the response data to handle different formats

        // Handle the case when response data is a List (like for MC_Code)
        if (response.data is List) {
          // Convert the list to a map with a 'data' key
          return {
            'success': true,
            'data': response.data,
            'message': 'Data retrieved successfully'
          };
        }

        // Handle other formats (Map, String, etc.)
        Map<String, dynamic> processedData;

        if (response.data is Map) {
          processedData = Map<String, dynamic>.from(response.data);
        } else if (response.data is String) {
          try {
            processedData = json.decode(response.data);
          } catch (e) {
            return {
              'success': true,
              'message': 'Failed to parse response: ${e.toString()}'
            };
          }
        } else {
          return {
            'success': false,
            'message':
                'Unexpected response format: ${response.data.runtimeType}'
          };
        }

        // Check if the response has the records key
        if (processedData.containsKey('records')) {
          // Group records by RecordTypeName
          final recordsData = processedData['records'] as List<dynamic>;

          // Create a map to store records by type
          Map<String, List<Map<String, dynamic>>> recordsByType = {};

          // Process each record
          for (var record in recordsData) {
            if (record is Map) {
              final recordMap = Map<String, dynamic>.from(record);
              final recordTypeName =
                  recordMap['RecordTypeName'] as String? ?? 'Unknown';

              // Initialize the list for this record type if it doesn't exist
              recordsByType[recordTypeName] ??= [];

              // Add this record to its type group
              recordsByType[recordTypeName]!.add(recordMap);
            }
          }

          // Store each record type group separately in Hive
          final recordsBox = await Hive.openBox('fetchcode');
          // Store the original response
          await recordsBox.put('fetchcode_records', processedData);

          try {
            await LocalJsonStorage.saveResponse('records', response.data);
            await LocalJsonStorage.saveResponse('all_records', response.data);
          } catch (e) {
            // Continue execution even if JSON storage fails
          }

          // Store each record type separately
          for (var entry in recordsByType.entries) {
            await recordsBox.put(entry.key, entry.value);
          }

          // Also store the list of available record types
          await recordsBox.put('record_types', recordsByType.keys.toList());

          return {
            'success': true,
            'data': {
              'all_records': processedData,
              'record_types': recordsByType.keys.toList(),
              'records_by_type': recordsByType,
            },
            'message': 'Records fetched and processed successfully'
          };
        } else {
          // If there's no 'records' key, store the response as-is
          await Hive.openBox('records').then((box) {
            box.put('records', processedData);
          });

          return {
            'success': true,
            'data': processedData,
            'message': 'Records fetched successfully'
          };
        }
      } else if (response.statusCode == 404) {
        return {'success': false, 'message': 'No records found'};
      } else if (response.statusCode == 400) {
        return {
          'success': false,
          'message': 'Invalid username or no records found'
        };
      } else {
        return {'success': false, 'message': 'No Records Found'};
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 404) {
        return {'success': false, 'message': 'No records found'};
      } else {
        return {
          'success': false,
          'message': 'Something went wrong in ListView'
        };
      }
    }
  }

  Future<Map<String, dynamic>> callImageApi(
      {required String workId,
      required List<Map<String, dynamic>> imageFiles}) async {
    try {
      // First get authentication token
      final authResult = await _getAuthToken();
      if (!authResult['success']) {
        return authResult; // Return error if authentication failed
      }

      final accessToken = authResult['data']['access_token'];

      // Make sure the accessToken is a String
      if (accessToken == null || !(accessToken is String)) {
        return {'success': false, 'message': 'Invalid access token format'};
      }

      // Store the token in Hive for future use
      // final box = await Hive.openBox('token_data');
      // await box.put('access_token', accessToken);

      // Create the payload as per required format
      // Check each file's base64Data to ensure it has proper quotes
      List<Map<String, dynamic>> sanitizedFiles = imageFiles.map((file) {
        Map<String, dynamic> sanitizedFile = Map.from(file);

        // Ensure base64Data is properly quoted for JSON
        if (sanitizedFile.containsKey('base64Data') &&
            sanitizedFile['base64Data'] is String) {
          String base64Data = sanitizedFile['base64Data'];

          // Ensure the base64 string is properly formatted for JSON
          if (!base64Data.endsWith('"')) {
            // This will be handled properly by json.encode
            // We don't need to manually add quotes as json.encode will do that
          }
        }

        return sanitizedFile;
      }).toList();

      final payload = {
        "Work_Id__c": workId,
        "files": sanitizedFiles,
      };

      // Debug the payload
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      String prettyJson = encoder.convert(payload);
      print('Image upload payload:');
      prettyJson.split('\n').forEach((line) => print(line));

      // Convert payload to JSON properly with json.encode
      String jsonPayload = json.encode(payload);

      // Verify the encoded JSON string has proper quotes around base64 data
      print(
          'First few chars of encoded JSON: ${jsonPayload.substring(0, 50)}...');

      final response = await _dio.post(
        'https://ltfs--sit.sandbox.my.salesforce.com/services/apexrest/rcu/fileUpload',
        data: jsonPayload, // Use the properly encoded JSON string
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        // Process response data to ensure proper typing
        Map<String, dynamic> processedData;

        if (response.data is Map) {
          processedData = Map<String, dynamic>.from(response.data);
        } else if (response.data is String) {
          try {
            processedData = json.decode(response.data);
          } catch (e) {
            return {
              'success': false,
              'message':
                  'Failed to parse image upload response: ${e.toString()}'
            };
          }
        } else {
          return {
            'success': false,
            'message':
                'Unexpected image upload response format: ${response.data.runtimeType}'
          };
        }

        // Save the upload results to local storage for reference
        try {
          // First check if we already have image uploads for this work ID
          final existingData =
              await LocalJsonStorage.readResponse('image_uploads') ?? {};
          Map<String, dynamic> uploadsData;

          if (existingData is Map) {
            uploadsData = Map<String, dynamic>.from(existingData);
          } else {
            uploadsData = {};
          }

          // Store this upload result by work ID
          uploadsData[workId] = processedData;

          await LocalJsonStorage.saveResponse('image_uploads', uploadsData);
        } catch (e) {
          // Continue execution even if JSON storage fails
        }

        // Check for success by examining the results array
        bool allUploadsSuccessful = true;
        List<String> failedUploads = [];

        if (processedData.containsKey('results') &&
            processedData['results'] is List) {
          List<dynamic> results = processedData['results'];

          for (var result in results) {
            if (result is Map && result.containsKey('status')) {
              if (result['status'] != 'SUCCESS') {
                allUploadsSuccessful = false;
                if (result.containsKey('fileName')) {
                  failedUploads.add(result['fileName'].toString());
                }
              }
            }
          }
        }

        // Add an overall success flag to the response
        processedData['success'] = allUploadsSuccessful;
        if (!allUploadsSuccessful) {
          processedData['failedUploads'] = failedUploads;
        }

        return processedData;
      } else {
        return {
          'success': false,
          'message':
              'Image upload failed with status code: ${response.statusCode}'
        };
      }
    } on DioException catch (e) {
      return {'success': false, 'message': 'Image upload error: ${e.message}'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Error during image upload: ${e.toString()}'
      };
    }
  }

  Future<Map<String, dynamic>> callTokenApi({String? username}) async {
    try {
      // First get authentication token
      final authResult = await _getAuthToken();
      if (!authResult['success']) {
        return authResult; // Return error if authentication failed
      }

      final accessToken = authResult['data']['access_token'];

      // Make sure the accessToken is a String
      if (accessToken == null || !(accessToken is String)) {
        return {'success': false, 'message': 'Invalid access token format'};
      }

      // Store the token in Hive for future use
      // final box = await Hive.openBox('token_data');
      // await box.put('access_token', accessToken);

      final payload = {
        "PS_No": username,
        "pageNumber": 1,
      };

      final response = await _dio.post(
        'https://ltfs--sit.sandbox.my.salesforce.com/services/apexrest/rcu/listview',
        data:
            json.encode(payload), // Ensure payload is properly encoded as JSON
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        // Process the response data to handle different formats
        Map<String, dynamic> processedData;

        if (response.data is Map) {
          processedData = Map<String, dynamic>.from(response.data);
        } else if (response.data is String) {
          try {
            processedData = json.decode(response.data);
          } catch (e) {
            return {
              'success': false,
              'message': 'Failed to parse response: ${e.toString()}'
            };
          }
        } else {
          return {
            'success': false,
            'message':
                'Unexpected response format: ${response.data.runtimeType}'
          };
        }

        // Check if the response has the records key
        if (processedData.containsKey('records')) {
          // Group records by RecordTypeName
          final recordsData = processedData['records'] as List<dynamic>;

          // Create a map to store records by type
          Map<String, List<Map<String, dynamic>>> recordsByType = {};

          // Process each record
          for (var record in recordsData) {
            if (record is Map) {
              final recordMap = Map<String, dynamic>.from(record);
              final recordTypeName =
                  recordMap['RecordTypeName'] as String? ?? 'Unknown';

              // Initialize the list for this record type if it doesn't exist
              recordsByType[recordTypeName] ??= [];

              // Add this record to its type group
              recordsByType[recordTypeName]!.add(recordMap);
            }
          }

          // Store each record type group separately in Hive
          final recordsBox = await Hive.openBox('records');
          // Store the original response
          await recordsBox.put('all_records', processedData);

          try {
            await LocalJsonStorage.saveResponse('records', response.data);
            await LocalJsonStorage.saveResponse('all_records', response.data);
          } catch (e) {
            // Continue execution even if JSON storage fails
          }

          // Store each record type separately
          for (var entry in recordsByType.entries) {
            await recordsBox.put(entry.key, entry.value);
          }

          // Also store the list of available record types
          await recordsBox.put('record_types', recordsByType.keys.toList());

          return {
            'success': true,
            'data': {
              'all_records': processedData,
              'record_types': recordsByType.keys.toList(),
              'records_by_type': recordsByType,
            },
            'message': 'Records fetched and processed successfully'
          };
        } else {
          // If there's no 'records' key, store the response as-is
          await Hive.openBox('records').then((box) {
            box.put('records', processedData);
          });

          return {
            'success': true,
            'data': processedData,
            'message': 'Records fetched successfully'
          };
        }
      } else if (response.statusCode == 404) {
        return {'success': false, 'message': 'No records found'};
      } else if (response.statusCode == 400) {
        return {
          'success': false,
          'message': 'Invalid username or no records found'
        };
      } else {
        return {'success': false, 'message': 'No Records Found'};
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.statusCode == 404) {
        return {'success': false, 'message': 'No records found'};
      } else {
        return {
          'success': false,
          'message': 'Something went wrong in ListView'
        };
      }
    }
  }
}

// Custom logger class for SSL Pinning
class _CustomLogger {
  void d(String message) {}

  void e(String message) {}
}
