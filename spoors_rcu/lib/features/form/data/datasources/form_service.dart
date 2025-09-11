import 'dart:convert';
import 'dart:io';
import 'package:BMS/core/network/LocalJsonStorage.dart';
import 'package:BMS/core/network/api_service.dart';
import 'package:flutter/material.dart';
import 'package:BMS/features/form/data/models/form_model.dart';
import 'package:hive/hive.dart';

class HiveService {
  // Modified to first check JSON files before using Hive
  static Future<List<FormModel>> loadFormFieldsFromHive(
      {String? recordType}) async {
    try {
      // Try to load from form_fields.json first
      final jsonData = await LocalJsonStorage.readResponse('form_fields');
      if (jsonData != null) {
        List<FormModel> fields = [];

        // Process based on data structure and record type
        if (jsonData is Map && jsonData.containsKey('recordTypes')) {
          // If structured by record type
          Map<String, dynamic> recordTypes = jsonData['recordTypes'];

          if (recordType != null && recordTypes.containsKey(recordType)) {
            // Get fields for specific record type
            var typeFields = recordTypes[recordType];
            if (typeFields is List) {
              for (var fieldData in typeFields) {
                if (fieldData is Map<String, dynamic>) {
                  fields.add(FormModel.fromJson(fieldData));
                }
              }
            }
          } else if (recordType == null) {
            // If no record type specified, return all fields
            for (var type in recordTypes.keys) {
              var typeFields = recordTypes[type];
              if (typeFields is List) {
                for (var fieldData in typeFields) {
                  if (fieldData is Map<String, dynamic>) {
                    fields.add(FormModel.fromJson(fieldData));
                  }
                }
              }
            }
          }
        } else if (jsonData is List) {
          // If it's just a flat list without record type differentiation
          // This is likely your current structure - we'll convert it later
          for (var fieldData in jsonData) {
            if (fieldData is Map<String, dynamic>) {
              // If the field has a recordType property, filter by it
              if (recordType != null &&
                  fieldData.containsKey('recordType') &&
                  fieldData['recordType'] != recordType) {
                continue; // Skip fields from other record types
              }
              fields.add(FormModel.fromJson(fieldData));
            }
          }
        }

        if (fields.isNotEmpty) {
          return fields;
        }
      }

      // Fall back to Hive if needed
      final box = await Hive.openBox('schema');
      final List<FormModel> fields = [];

      // If record type is provided, try to get type-specific schema first
      if (recordType != null) {
        var typeSchema = box.get(recordType);
        if (typeSchema != null) {
          if (typeSchema is List) {
            for (var item in typeSchema) {
              if (item is Map<String, dynamic>) {
                fields.add(FormModel.fromJson(item));
              }
            }
          } else if (typeSchema is Map && typeSchema['fields'] is List) {
            for (var item in typeSchema['fields']) {
              if (item is Map<String, dynamic>) {
                fields.add(FormModel.fromJson(item));
              }
            }
          }
        }
      }

      // If no record-type specific fields found, try generic schema
      if (fields.isEmpty) {
        final schema = box.get('schema');
        if (schema != null) {
          if (schema is List) {
            for (var item in schema) {
              if (item is Map<String, dynamic>) {
                fields.add(FormModel.fromJson(Map<String, dynamic>.from(item)));
              }
            }
          } else if (schema is Map && schema['fields'] is List) {
            for (var item in schema['fields']) {
              if (item is Map<String, dynamic>) {
                fields.add(FormModel.fromJson(Map<String, dynamic>.from(item)));
              }
            }
          }
        }
      }

      // If we loaded fields from Hive, save them to JSON for next time
      if (fields.isNotEmpty) {
        // Now save with record type information
        await saveFormFieldsToJson(fields, recordType: recordType);
      }

      return fields;
    } catch (e) {
      // Return empty list as fallback
      return [];
    }
  }

  // Modified to save to both Hive and JSON
  static Future<void> saveFormFieldToHive(FormModel field,
      {String? recordType}) async {
    try {
      // Add recordType to the field data if provided
      if (recordType != null) {
        field.recordType = recordType;
      }

      // First save to Hive
      final box = await Hive.openBox('formFields');
      await box.put(field.apiName, field.toJson());

      // Then update JSON file with all fields
      final allFields = await loadFormFieldsFromHive(recordType: recordType);

      // Check if this field already exists in the list
      bool fieldExists = false;
      for (int i = 0; i < allFields.length; i++) {
        if (allFields[i].apiName == field.apiName) {
          allFields[i] = field; // Update the existing field
          fieldExists = true;
          break;
        }
      }

      // If field doesn't exist in the list, add it
      if (!fieldExists) {
        allFields.add(field);
      }

      // Save the updated list to JSON
      await saveFormFieldsToJson(allFields, recordType: recordType);
    } catch (e) {}
  }

  // New method to save all form fields to JSON
  static Future<void> saveFormFieldsToJson(List<FormModel> fields,
      {String? recordType}) async {
    try {
      // First load existing data to preserve other record types
      dynamic existingData =
          await LocalJsonStorage.readResponse('form_fields') ??
              {'recordTypes': {}};
      Map<String, dynamic> formFieldsData;

      if (existingData is List) {
        // Convert old format to new format
        formFieldsData = {'recordTypes': {}};
      } else if (existingData is Map) {
        formFieldsData = Map<String, dynamic>.from(existingData);
        if (!formFieldsData.containsKey('recordTypes')) {
          formFieldsData['recordTypes'] = {};
        }
      } else {
        formFieldsData = {'recordTypes': {}};
      }

      // Convert fields to JSON-serializable format
      final List<Map<String, dynamic>> jsonList = fields.map((field) {
        var json = field.toJson();
        // Add recordType to the field data if provided
        if (recordType != null) {
          json['recordType'] = recordType;
        }
        return json;
      }).toList();

      // Organize by record type
      if (recordType != null) {
        // Save under specific record type
        formFieldsData['recordTypes'][recordType] = jsonList;
      } else {
        // If no record type specified, try to organize by existing recordType property
        Map<String, List<Map<String, dynamic>>> fieldsByType = {};

        for (var fieldJson in jsonList) {
          String type = fieldJson['recordType'] ?? 'generic';
          if (!fieldsByType.containsKey(type)) {
            fieldsByType[type] = [];
          }
          fieldsByType[type]!.add(fieldJson);
        }

        // Update each record type's fields
        for (var type in fieldsByType.keys) {
          formFieldsData['recordTypes'][type] = fieldsByType[type]!;
        }
      }

      // Save to JSON file using LocalJsonStorage
      await LocalJsonStorage.saveResponse('form_fields', formFieldsData);
    } catch (e) {}
  }

  // Existing method unchanged
  static Map<String, dynamic> createFormPayload(
      List<FormModel> formFields, String? recordId, String? username) {
    // Create the outer structure
    Map<String, dynamic> payload = {
      'recordId': recordId,
      //'Current_User_PS_ID': HiveService.getCurrentUserId(),
      'Current_User_PS_ID': username,
      'recordType': formFields.first.recordType,
      'fieldValues': {},
    };

    // Add each field value to the fieldValues map
    for (var field in formFields) {
      if (field.value != null &&
          field.editable &&
          //field.type != 'REFERENCE') {
          field.pageType == 'Form') {
        var fieldValue = field.value;

        // Handle boolean values explicitly
        if (fieldValue?.toLowerCase() == 'true') {
          payload['fieldValues'][field.apiName] = true;
        } else if (fieldValue?.toLowerCase() == 'false') {
          payload['fieldValues'][field.apiName] = false;
        } else if (field.type == 'Checkbox' || field.type == 'Boolean') {
          // Handle checkbox fields
          bool boolValue =
              fieldValue == 'true' || fieldValue == '1' || fieldValue == 'yes';
          payload['fieldValues'][field.apiName] = boolValue;
        } else if (field.type == 'Number' &&
            fieldValue is String &&
            fieldValue.isNotEmpty) {
          // Try to convert numeric strings to actual numbers
          try {
            if (fieldValue.contains('.')) {
              payload['fieldValues'][field.apiName] = double.parse(fieldValue);
            } else {
              payload['fieldValues'][field.apiName] = int.parse(fieldValue);
            }
          } catch (e) {
            // If parsing fails, keep as string
            payload['fieldValues'][field.apiName] = fieldValue;
          }
        } else {
          payload['fieldValues'][field.apiName] = fieldValue;
        }
      }
    }

    return payload;
  }

  // Add this method to the HiveService class
  static Future<String> getCurrentUserId() async {
    try {
      final userBox = await Hive.openBox('auth');
      final storedUsername = userBox.get('username', defaultValue: 'User');
      // Check for username key first (this is what you use in startuppage.dart)
      String? userId = userBox.get('username') as String?;

      // If not found, try other possible keys
      if (userId == null || userId.isEmpty) {
        userId = userBox.get('user_id') as String?;
      }

      if (userId == null || userId.isEmpty) {
        userId = userBox.get('userId') as String?;
      }

      print('Retrieved user ID from Hive: ${userId ?? 'NOT FOUND'}');

      // Return the found ID or a default
      // return userId ?? '';
      return storedUsername ?? '';
    } catch (e) {
      print('Error retrieving user ID: $e');
      return '';
    }
  }

  // Add this method to store the user ID when user logs in
  static Future<void> saveCurrentUserId(String userId) async {
    try {
      // final userBox = await Hive.openBox('auth');
      // await userBox.put('user_id', userId);
      print('User ID saved: $userId');
    } catch (e) {
      print('Error saving user ID: $e');
    }
  }
}

class FormApiService {
  final ApiCall _apiCall = ApiCall();

  // Modified to add JSON caching of results
  Future<Map> submitForm({
    required String recordType,
    required List<FormModel> formFields,
    String? recordId,
    String? uid,
    String? username,
  }) async {
    try {
      // Create payload using the form fields
      final payload = HiveService.createFormPayload(formFields, uid, username);

      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      String prettyJson = encoder.convert(payload);
      prettyJson.split('\n').forEach((line) => print(line));

      // Call the API using your existing API service
      final result = await _apiCall.callApi(
        endpoint: 'submit',
        title: recordType,
        data: payload,
      );

      // Cache the result for this record ID in a JSON file
      if (result['success'] == true && recordId != null) {
        try {
          // Create a submissions record to track all submissions
          final submissionsData =
              await LocalJsonStorage.readResponse('form_submissions') ?? {};

          // If data is a List instead of a Map, convert to Map
          Map<String, dynamic> submissionsMap;
          if (submissionsData is List) {
            submissionsMap = {'submissions': submissionsData};
          } else {
            //submissionsMap = submissionsData as Map<String, dynamic>;
            submissionsMap = (submissionsData as Map)
                .map((key, value) => MapEntry(key.toString(), value));
          }

          // Initialize submissions array if needed
          if (!submissionsMap.containsKey('submissions')) {
            submissionsMap['submissions'] = [];
          }

          // Add this submission to the list
          submissionsMap['submissions'].add({
            'recordId': recordId,
            'recordType': recordType,
            'submissionTime': DateTime.now().toIso8601String(),
            'success': true,
            'responseData': result,
          });

          // Save updated submissions data
          await LocalJsonStorage.saveResponse(
              'form_submissions', submissionsMap);
        } catch (e) {
          // Continue execution even if caching fails
        }
      }

      // Handle the result properly with null safety
      if (result.containsKey('Success_Code') &&
          result['Success_Code'] == '1') {}

      return result;
    } catch (e) {
      // Cache failed submissions too for retry logic
      if (recordId != null) {
        try {
          final submissionsData =
              await LocalJsonStorage.readResponse('form_submissions') ?? {};

          // If data is a List instead of a Map, convert to Map
          Map<String, dynamic> submissionsMap;
          if (submissionsData is List) {
            submissionsMap = {'submissions': submissionsData};
          } else {
            //submissionsMap = submissionsData as Map<String, dynamic>;
            submissionsMap = (submissionsData as Map)
                .map((key, value) => MapEntry(key.toString(), value));
          }

          // Initialize submissions array if needed
          if (!submissionsMap.containsKey('submissions')) {
            submissionsMap['submissions'] = [];
          }

          // Add this failed submission to the list
          submissionsMap['submissions'].add({
            'recordId': recordId,
            'recordType': recordType,
            'submissionTime': DateTime.now().toIso8601String(),
            'success': false,
            'error': e.toString(),
          });

          await LocalJsonStorage.saveResponse(
              'form_submissions', submissionsMap);
        } catch (jsonError) {
          // Continue execution even if caching fails
        }
      }

      return {
        'success': false,
        'message': 'Error submitting form: ${e.toString()}',
      };
    }
  }

  // New method to load submission history
  Future<List<Map<String, dynamic>>> getFormSubmissionHistory() async {
    try {
      final submissionsData =
          await LocalJsonStorage.readResponse('form_submissions');

      if (submissionsData == null) {
        return [];
      }

      if (submissionsData is Map &&
          submissionsData.containsKey('submissions')) {
        final submissions = submissionsData['submissions'];
        if (submissions is List) {
          return List<Map<String, dynamic>>.from(submissions
              .map((e) => e is Map ? Map<String, dynamic>.from(e) : {}));
        }
      } else if (submissionsData is List) {
        return List<Map<String, dynamic>>.from(submissionsData
            .map((e) => e is Map ? Map<String, dynamic>.from(e) : {}));
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  // Get uploaded images for a specific work ID
  Future<List<Map<String, dynamic>>> getUploadedImagesForWorkId(
      String workId) async {
    try {
      final uploadsData = await LocalJsonStorage.readResponse('image_uploads');

      if (uploadsData == null || !(uploadsData is Map)) {
        return [];
      }

      final Map<String, dynamic> uploadsMap =
          Map<String, dynamic>.from(uploadsData);
      if (!uploadsMap.containsKey(workId)) {
        return [];
      }

      final workData = uploadsMap[workId];
      if (workData is Map &&
          workData.containsKey('results') &&
          workData['results'] is List) {
        List<dynamic> results = workData['results'];
        return results
            .where((result) => result is Map)
            .map((result) => Map<String, dynamic>.from(result))
            .toList();
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  // Helper method to prepare image data for upload
  static Map<String, String> prepareImageForUpload(
      String fileName, String contentType, String base64Data) {
    return {
      "fileName": fileName,
      "contentType": contentType,
      "base64Data": base64Data
    };
  }

  // Helper method to prepare image file for upload
  static Future<Map<String, String>?> prepareImageFileForUpload(File imageFile,
      {String? customFileName}) async {
    try {
      // Get file extension
      String fileName = customFileName ?? imageFile.path.split('/').last;

      // Determine content type based on file extension
      String contentType;
      if (fileName.toLowerCase().endsWith('.png')) {
        contentType = 'image/png';
      } else if (fileName.toLowerCase().endsWith('.jpg') ||
          fileName.toLowerCase().endsWith('.jpeg')) {
        contentType = 'image/jpeg';
      } else if (fileName.toLowerCase().endsWith('.pdf')) {
        contentType = 'application/pdf';
      } else {
        // Default to octet-stream if can't determine
        contentType = 'application/octet-stream';
      }

      // Read file as bytes and convert to base64
      List<int> imageBytes = await imageFile.readAsBytes();
      String base64Data = base64Encode(imageBytes);

      return {
        "fileName": fileName,
        "contentType": contentType,
        "base64Data": base64Data
      };
    } catch (e) {
      return null;
    }
  }
}
