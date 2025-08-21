import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class LocalJsonStorage {
  // Use methods to get file paths dynamically
  static Future<String> _getFilePath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/utils/$fileName';
  }

  static Future<File> _getFile(String apiName) async {
    String fileName;
    switch (apiName) {
      case 'schema':
        fileName = 'schema.json';
        break;
      case 'records':
        fileName = 'records.json';
        break;
      case 'all_records':
        fileName = 'all_records.json';
        break;
      case 'form_fields':
        fileName = 'form_fields.json';
        break;
      case 'form_submissions':
        fileName = 'form_submissions.json';
        break;
      default:
        throw Exception('❌ Unknown API name: $apiName');
    }

    final path = await _getFilePath(fileName);
    final file = File(path);

    // Ensure the parent folder exists
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    return file;
  }

  /// Save response data after clearing any existing data in the file
  static Future<void> saveResponse(String apiName, dynamic data) async {
    final file = await _getFile(apiName);

    // Ensure data is serializable (either Map or List)
    if (data is Map || data is List) {
      try {
        // Delete the file if it exists
        if (await file.exists()) {
          await file.delete();
        }

        // Create a fresh file and write the data
        await file.writeAsString(jsonEncode(data));
      } catch (e) {
        rethrow; // Re-throw to allow caller to handle the error
      }
    } else {
      throw ArgumentError(
          'Data must be either Map or List for JSON serialization');
    }
  }

  /// Save response data by appending to or updating existing data
  static Future<void> updateResponse(String apiName, dynamic data,
      {String? idField}) async {
    // Read existing data
    final existingData = await readResponse(apiName);

    if (existingData == null) {
      // If no existing data, just save the new data
      return saveResponse(apiName, data);
    }

    try {
      // Merge or append data based on type
      if (existingData is Map && data is Map) {
        // Merge maps
        existingData.addAll(data);
        await saveResponse(apiName, existingData);
      } else if (existingData is List && data is List) {
        // For lists, we can either replace the whole list or merge items
        if (idField != null) {
          // If an ID field is specified, update existing items or add new ones
          final updatedList = [...existingData];

          for (var newItem in data) {
            if (newItem is Map && newItem.containsKey(idField)) {
              // Find matching item in existing list
              final existingIndex = updatedList.indexWhere(
                (item) => item is Map && item[idField] == newItem[idField],
              );

              if (existingIndex >= 0) {
                // Update existing item
                updatedList[existingIndex] = newItem;
              } else {
                // Add new item
                updatedList.add(newItem);
              }
            } else {
              // No ID field, just add
              updatedList.add(newItem);
            }
          }

          await saveResponse(apiName, updatedList);
        } else {
          // No ID field, just append all items
          final updatedList = [...existingData, ...data];
          await saveResponse(apiName, updatedList);
        }
      } else if (existingData is Map && data is List) {
        // Special case for records.json where we might have record types as keys
        if (apiName == 'records') {
          for (final item in data) {
            if (item is Map && item.containsKey('RecordTypeName')) {
              final recordType = item['RecordTypeName'];
              if (!existingData.containsKey(recordType)) {
                existingData[recordType] = [];
              }

              if (existingData[recordType] is List) {
                // Add to appropriate record type list if not already there
                final List typeList = existingData[recordType];
                final existingIndex = typeList.indexWhere(
                  (record) =>
                      record is Map &&
                      record['Work_Id__c'] == item['Work_Id__c'],
                );

                if (existingIndex >= 0) {
                  typeList[existingIndex] = item; // Update
                } else {
                  typeList.add(item); // Add
                }
              }
            }
          }

          await saveResponse(apiName, existingData);
        } else {
          // For other files, replace with new data
          await saveResponse(apiName, data);
        }
      } else {
        // Different types, just replace with new data
        await saveResponse(apiName, data);
      }
    } catch (e) {
      // If update fails, try a clean save
      await saveResponse(apiName, data);
    }
  }

  static Future<dynamic> readResponse(String apiName) async {
    final file = await _getFile(apiName);
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      return jsonDecode(content);
    } catch (e) {
      return null;
    }
  }

  static Future<void> clearResponse(String apiName) async {
    final file = await _getFile(apiName);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Clear all JSON storage files
  static Future<void> clearAllFiles() async {
    try {
      final apiNames = [
        'schema',
        'records',
        'all_records',
        'form_fields',
        'form_submissions'
      ];
      for (final apiName in apiNames) {
        await clearResponse(apiName);
      }
    } catch (e) {}
  }

  /// Get information about stored files
  static Future<Map<String, dynamic>> getStorageInfo() async {
    final result = <String, dynamic>{};
    final apiNames = [
      'schema',
      'records',
      'all_records',
      'form_fields',
      'form_submissions'
    ];

    try {
      for (final apiName in apiNames) {
        final file = await _getFile(apiName);
        if (await file.exists()) {
          final stats = await file.stat();
          result[apiName] = {
            'exists': true,
            'size': stats.size,
            'modified': stats.modified.toIso8601String(),
          };
        } else {
          result[apiName] = {'exists': false};
        }
      }
    } catch (e) {}

    return result;
  }
}
