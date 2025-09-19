import 'package:BMS/core/common_widgets/bottomnavbar.dart';
import 'package:BMS/core/common_widgets/hamburger.dart';
import 'package:BMS/core/constants/constants.dart';
import 'package:BMS/core/network/api_service.dart';
import 'package:BMS/features/dashboard/presentation/widgets/bottomsheet.dart';
import 'package:BMS/features/form/presentation/pages/form.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../../../core/network/LocalJsonStorage.dart';
import 'package:lottie/lottie.dart';

class Workid extends StatefulWidget {
  final String title;
  final String recordType;
  final String? recordId;
  final String? uid;
  final String? username;
  //final List<String>? recordlist;
  // Add this to define the tabs
  // Add this parameter

  const Workid({
    Key? key,
    required this.title,
    required this.recordType,
    this.recordId, // Make it optional to maintain backward compatibility
    this.uid,
    this.username,
    //this.recordlist,
  }) : super(key: key);

  @override
  State<Workid> createState() => _WorkidState();
}

class _WorkidState extends State<Workid> {
  int selectedTab = 0;
  late Box box;
  var storedIds;
  bool isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? recordData; // Add this to store the loaded record data

  @override
  void initState() {
    super.initState();
    _initHiveBox();
  }

//Future<void> _loadRecordById(List<String>? recordlist) async {
  Future<void> _loadRecordById(String recordId) async {
    try {
      Map<String, dynamic>? data;

      // First try to find the record in JSON files

      // Check in records.json
      final recordsJsonData = await LocalJsonStorage.readResponse('records');
      if (recordsJsonData != null) {
        // Check each record type collection
        for (var key in recordsJsonData.keys) {
          if (recordsJsonData[key] is List) {
            for (var record in recordsJsonData[key]) {
              if (record is Map && record['Work_Id__c'] == recordId) {
                data = Map<String, dynamic>.from(record);
                break;
              }
            }
          }
          if (data != null) break;
        }
      }

      // If not found, check in all_records.json
      if (data == null) {
        final allRecordsJsonData =
            await LocalJsonStorage.readResponse('all_records');
        if (allRecordsJsonData != null &&
            allRecordsJsonData['records'] is List) {
          for (var record in allRecordsJsonData['records']) {
            if (record is Map && record['Work_Id__c'] == recordId) {
              data = Map<String, dynamic>.from(record);
              break;
            }
          }
        }
      }

      // If still not found, fall back to Hive
      if (data == null) {
        final box = await Hive.openBox('records');

        // Try direct lookup in Hive
        var hiveData = box.get(recordId);

        // If direct lookup fails, check in all_records
        if (hiveData == null) {
          final allRecords = box.get('all_records');
          if (allRecords != null && allRecords['records'] is List) {
            // Search for the record by ID in the records list
            for (var record in allRecords['records']) {
              if (record is Map && record['Work_Id__c'] == recordId) {
                hiveData = record;
                break;
              }
            }

            // If still not found, check in each record type collection
            if (hiveData == null) {
              final recordTypes = box.get('record_types');
              if (recordTypes is List) {
                for (var recordType in recordTypes) {
                  final typeRecords = box.get(recordType);
                  if (typeRecords is List) {
                    for (var record in typeRecords) {
                      if (record is Map && record['Work_Id__c'] == recordId) {
                        hiveData = record;
                        break;
                      }
                    }
                    if (hiveData != null) break;
                  }
                }
              }
            }
          }
        } else {}

        // Convert Hive data to Map if found
        if (hiveData != null) {
          if (hiveData is Map) {
            data = Map<String, dynamic>.from(hiveData);
          } else if (hiveData is List &&
              hiveData.isNotEmpty &&
              hiveData[0] is Map) {
            data = Map<String, dynamic>.from(hiveData[0]);
          } else {
            data = {
              'Id': recordId,
              'RecordTypeName': widget.title,
              'data': hiveData.toString(),
            };
          }
        }
      }

      // Process the data if found
      if (data != null) {
        setState(() {
          recordData = data;

          // Ensure the record has all required fields
          if (!recordData!.containsKey('Work_Id__c')) {
            recordData!['Work_Id__c'] = recordId;
          }

          if (!recordData!.containsKey('RecordTypeName')) {
            recordData!['RecordTypeName'] = widget.title;
          }

          // Create a proper list structure for the UI
          if (recordData!.containsKey('records') &&
              recordData!['records'] is List) {
            storedIds = recordData;
          } else {
            storedIds = [recordData];
          }
        });
      } else {
        setState(() {
          recordData = null;
          storedIds = [];
        });

        // Show a message to the user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Record with ID $recordId not found')),
        );
      }
    } catch (e) {
      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading record: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Future<void> _loadRecordById(String recordId) async {
  //   try {
  //     final box = await Hive.openBox('records');
  //     final data = box.get(recordId);

  //     if (data != null) {
  //       setState(() {
  //         // Convert the data to a Map if it isn't already
  //         if (data is Map) {
  //           recordData = Map<String, dynamic>.from(data);
  //         } else {
  //           recordData = {'data': data};
  //         }

  //         // Create a list with this record and store it for the UI
  //         storedIds = [recordData];
  //       });
  //     } else {
  //     }
  //   } catch (e) {
  //   } finally {
  //     setState(() {
  //       isLoading = false;
  //     });
  //   }
  // }

  String replaceSpacesWithUnderscores(String input) {
    return input.replaceAll(' ', '_');
  }

  Future<void> _initHiveBox() async {
    setState(() {
      _errorMessage = null;
      isLoading = true;
      storedIds = [];
    });

    try {
      String title_text = replaceSpacesWithUnderscores(widget.title);

      // Load schema from JSON
      final schemaRaw = await LocalJsonStorage.readResponse('schema');
      // Don't assume schemaRaw is a Map<String, dynamic>
      if (schemaRaw != null) {
      } else {
        // Fallback to API
        final ApiCall apiCall = ApiCall();
        final result =
            await apiCall.callApi(endpoint: 'schema', title: title_text);

        if (!result['success']) {
          setState(() {
            _errorMessage = 'Failed to load schema: ${result["message"]}';
            isLoading = false;
          });
          return;
        }
      }

      // Load records from local JSON
      final recordsRaw = await LocalJsonStorage.readResponse('records');
      final allRecordsRaw = await LocalJsonStorage.readResponse('all_records');

      // Handle both Map and List data types
      dynamic recordsData = recordsRaw;
      dynamic allRecordsData = allRecordsRaw;

      if (recordsData != null) {}

      List<dynamic>? matchingRecords;

      // Try to find records in records.json
      if (recordsData != null) {
        if (recordsData is Map) {
          final recordsForType = recordsData[widget.title];
          if (recordsForType is List && recordsForType.isNotEmpty) {
            matchingRecords = recordsForType;
          }
        } else if (recordsData is List) {
          // If records is directly a list, filter by record type
          final filteredRecords = recordsData
              .where((record) =>
                  record is Map && record['RecordTypeName'] == widget.title)
              .toList();
          if (filteredRecords.isNotEmpty) {
            matchingRecords = filteredRecords;
          }
        }
      }

      // Fallback to all_records.json
      if (matchingRecords == null && allRecordsData != null) {
        // Check all_records.json for ${widget.title} records
        if (allRecordsData is List) {
          // Handle list format directly
          matchingRecords = allRecordsData
              .where((record) =>
                  record is Map && record['RecordTypeName'] == widget.title)
              .toList();
        } else if (allRecordsData is Map) {
          // Handle map format
          final records = allRecordsData['records'];
          if (records is List) {
            matchingRecords = records
                .where((record) =>
                    record is Map && record['RecordTypeName'] == widget.title)
                .toList();
          }
        }
        if (matchingRecords != null && matchingRecords.isNotEmpty) {}
      }

      // Fallback to Hive
      if (matchingRecords == null) {
        final box = await Hive.openBox('records');
        final recordsForType = box.get(widget.title);

        if (recordsForType is List && recordsForType.isNotEmpty) {
          matchingRecords = recordsForType;
        } else {
          final allRecords = box.get('all_records');
          if (allRecords is Map && allRecords['records'] is List) {
            final List<dynamic> records = allRecords['records'];
            matchingRecords = records
                .where((record) =>
                    record is Map && record['RecordTypeName'] == widget.title)
                .toList();
            if (matchingRecords.isNotEmpty) {
              // Found matching records in Hive
            }
          }
        }
      }

      // Set state with found records
      setState(() {
        storedIds = matchingRecords ?? [];
      });

      // Load individual record
      // if (widget.recordId != null) {
      //   _loadRecordById(widget.recordId!);
      // }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred: ${e.toString()}';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Future<void> _initHiveBox() async {
  //   setState(() {
  //     _errorMessage = null;
  //   });

  //   try {
  //     String title_text = replaceSpacesWithUnderscores(widget.title);
  //     final ApiCall apiCall = ApiCall();
  //     final result =
  //         await apiCall.callApi(endpoint: 'schema', title: title_text);

  //     if (result['success']) {
  //     }
  //   } catch (e) {
  //     setState(() {
  //       _errorMessage = 'An error occurred: ${e.toString()}';
  //       //_isLoading = false;
  //     });
  //   }
  // }

  final List<String> statusTabs = [
    'All',
    'Pending',
    'Complete',
    'Approved',
    'Rejected'
  ];

  final List<Color> cardColors = [
    Colors.blue,
    Colors.yellow,
    Colors.green,
    Colors.red
  ];

  // Open form for viewing or editing a record
  // void _openForm(String recordType, String? recordId) {
  //   Navigator.push(
  //     context,
  //     MaterialPageRoute(
  //       builder: (context) => DynamicFormScreen(
  //         //recordType: recordType,
  //         recordId: recordId,
  //         //formFields: const [], // This will be populated by API response
  //       ),
  //     ),
  //   );
  // }

// Updated method to pass both recordId and recordType
  // Updated method to handle the form result
  void _openForm(String recordType, String? recordId, String? uid) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: Lottie.asset(
                  'assets/animations/Loading1.json',
                  frameRate: FrameRate.max,
                  repeat: true,
                  animate: true,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Loading form data...',
                style: TextStyle(
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Ensure schema is ready
    await _ensureSchemaForRecordType(recordType);

    // Dismiss the loading dialog before showing the form
    if (context.mounted) Navigator.of(context).pop();

    print('Opening form for recordType: ${widget.username}');
    // Now open the form
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DynamicFormScreen(
          recordId: recordId,
          recordType: recordType,
          uid: uid,
          username: widget.username,
          schemaLoader: () async {
            try {
              // Try to load from JSON files first
              final schemaJsonData =
                  await LocalJsonStorage.readResponse('schema');
              if (schemaJsonData != null) {
                List<dynamic> fields = [];
                bool foundSpecificFields = false;

                // Try multiple matching strategies
                if (schemaJsonData is Map &&
                    schemaJsonData.containsKey('recordTypes')) {
                  // Check exact match first
                  if (schemaJsonData['recordTypes'].containsKey(recordType)) {
                    fields = schemaJsonData['recordTypes'][recordType];
                    foundSpecificFields = true;
                  }

                  // Try with spaces replaced with underscores
                  if (!foundSpecificFields) {
                    String recordTypeAlt = recordType.replaceAll(' ', '_');
                    if (schemaJsonData['recordTypes']
                        .containsKey(recordTypeAlt)) {
                      fields = schemaJsonData['recordTypes'][recordTypeAlt];
                      foundSpecificFields = true;
                    }
                  }
                }

                // If not found in organized structure, try in flat list
                if (!foundSpecificFields && schemaJsonData is List) {
                  fields = schemaJsonData.where((field) {
                    if (field is! Map) return false;

                    // Check if recordType matches directly
                    if (field['recordType'] == recordType) return true;

                    // Check with spaces replaced with underscores
                    String recordTypeAlt = recordType.replaceAll(' ', '_');
                    if (field['recordType'] == recordTypeAlt) return true;

                    return false;
                  }).toList();

                  if (fields.isNotEmpty) {
                    foundSpecificFields = true;
                  }
                }

                // If still nothing found, use default fields as fallback
                if (!foundSpecificFields || fields.isEmpty) {
                  // Try to get default fields
                  if (schemaJsonData is Map &&
                      schemaJsonData.containsKey('fields')) {
                    fields = schemaJsonData['fields'];
                  } else if (schemaJsonData is List) {
                    // If it's a flat list, use fields without a recordType as defaults
                    fields = schemaJsonData
                        .where((field) =>
                            field is Map &&
                            (!field.containsKey('recordType') ||
                                field['recordType'] == null))
                        .toList();
                  }

                  // Tag these fields with this record type for future use
                  for (var i = 0; i < fields.length; i++) {
                    if (fields[i] is Map) {
                      fields[i] = Map<String, dynamic>.from(fields[i]);
                      fields[i]['recordType'] = recordType;
                    }
                  }
                }

                // Debug output
                if (fields.isNotEmpty) {}

                return fields;
              }

              // If JSON files don't have schema, fall back to Hive
              final box = await Hive.openBox('schema');

              // First try record type specific data
              var fieldData = box.get(recordType);
              if (fieldData == null) {
                // Try with spaces replaced with underscores
                fieldData = box.get(recordType.replaceAll(' ', '_'));
              }

              // If still not found, try the generic schema
              if (fieldData == null) {
                fieldData = box.get('schema');
              } else {
                // Found specific schema for recordType in Hive
              }

              // Convert to list of fields
              List<dynamic> fields = [];
              if (fieldData is List) {
                fields = fieldData;
              } else if (fieldData is Map && fieldData['fields'] is List) {
                fields = fieldData['fields'];
              }

              // Tag these fields with this record type for future use
              for (var i = 0; i < fields.length; i++) {
                if (fields[i] is Map) {
                  fields[i] = Map<String, dynamic>.from(fields[i]);
                  fields[i]['recordType'] = recordType;
                }
              }

              // Save to JSON for future use
              if (fields.isNotEmpty) {
                await _saveSchemaFields(fields, recordType);
              }

              return fields;
            } catch (e) {
              // Error loading schema
              return [];
            }
          },
        ),
      ),
    );

    // Handle the result from the form
    if (result != null && result is Map && result['success'] == true) {
      String updatedRecordId = result['recordId'];
      String newStatus = result['newStatus'];

      // Update the record status in Hive, JSON files, and UI
      _updateRecordStatusAfterFormSubmission(updatedRecordId, newStatus);
    }
  }

// Method to update record status after form submission
  Future<void> _updateRecordStatusAfterFormSubmission(
      String recordId, String newStatus) async {
    try {
      bool updated = false;

      // Update the status in our local state first
      if (storedIds is List) {
        for (int i = 0; i < storedIds.length; i++) {
          if (storedIds[i]['Work_Id__c'] == recordId ||
              storedIds[i]['recordId'] == recordId) {
            setState(() {
              // storedIds[i]['Disbursement_status__c'] = newStatus;
              storedIds[i]['status'] = newStatus;
            });
            updated = true;
            // Updated record status in UI
            break;
          }
        }
      }

      // Try to update in JSON files first
      // Attempting to update record in JSON files...
      bool jsonUpdated = false;

      // Update in records.json
      final recordsJsonData = await LocalJsonStorage.readResponse('records');
      // Checking records.json for record $recordId...
      if (recordsJsonData != null) {
        bool foundInJson = false;

        // Check each record type collection
        for (var key in recordsJsonData.keys) {
          if (recordsJsonData[key] is List) {
            List<dynamic> records = recordsJsonData[key];
            for (int i = 0; i < records.length; i++) {
              if (records[i] is Map && records[i]['Work_Id__c'] == recordId) {
                //records[i]['Disbursement_status__c'] = newStatus;
                records[i]['status'] = newStatus;
                foundInJson = true;
                break;
              }
            }
          }
          if (foundInJson) break;
        }

        if (foundInJson) {
          await LocalJsonStorage.saveResponse('records', recordsJsonData);
          jsonUpdated = true;
          // Updated record in records.json
        }
      }

      // Update in all_records.json
      final allRecordsJsonData =
          await LocalJsonStorage.readResponse('all_records');
      if (allRecordsJsonData != null && allRecordsJsonData['records'] is List) {
        List<dynamic> records = allRecordsJsonData['records'];
        bool foundInAll = false;

        for (int i = 0; i < records.length; i++) {
          if (records[i] is Map && records[i]['Work_Id__c'] == recordId) {
            //records[i]['Disbursement_status__c'] = newStatus;
            records[i]['status'] = newStatus;
            foundInAll = true;
            break;
          }
        }

        if (foundInAll) {
          await LocalJsonStorage.saveResponse(
              'all_records', allRecordsJsonData);
          jsonUpdated = true;
        }
      }

      // If JSON files weren't updated or don't exist, fall back to Hive
      if (!jsonUpdated) {
        final recordsBox = await Hive.openBox('records');

        // 1. Check in the record type specific storage
        var typeRecords = recordsBox.get(widget.title);
        if (typeRecords is List) {
          bool foundInType = false;
          for (int i = 0; i < typeRecords.length; i++) {
            if (typeRecords[i]['Work_Id__c'] == recordId) {
              //typeRecords[i]['Disbursement_status__c'] = newStatus;
              typeRecords[i]['status'] = newStatus;
              foundInType = true;
              break;
            }
          }
          if (foundInType) {
            await recordsBox.put(widget.title, typeRecords);
            // Updated record in Hive ${widget.title} collection
          }
        }

        // 2. Check in all_records in Hive
        var allRecords = recordsBox.get('all_records');
        if (allRecords is Map && allRecords['records'] is List) {
          List<dynamic> records = allRecords['records'];
          bool foundInAll = false;
          for (int i = 0; i < records.length; i++) {
            if (records[i]['Work_Id__c'] == recordId) {
              //records[i]['Disbursement_status__c'] = newStatus;
              records[i]['status'] = newStatus;
              foundInAll = true;
              break;
            }
          }
          if (foundInAll) {
            await recordsBox.put('all_records', allRecords);
          }
        }
      }

      // Show success message if the UI was updated
      if (updated) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Record status updated to $newStatus')),
        );

        // Force a rebuild of the tabs
        setState(() {});
      }

      // After updating statuses in storedIds, add this:
      int pendingCount = 0;
      if (storedIds is List && storedIds.isNotEmpty) {
        pendingCount = storedIds.where((record) {
          final status = record['status'] ?? 'Pending';
          return status != 'Complete' && status != 'Completed';
        }).length;
      }

      // Only pop if the status was just changed (to avoid popping on every update)
      if (updated) {
        if (pendingCount == 0) {
          Navigator.pop(context, {
            'completedRecordType': widget.title,
            'pendingCount': 0,
          });
        } else {
          Navigator.pop(context, {
            'updatedRecordType': widget.title,
            'pendingCount': pendingCount,
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating record status: $e')),
      );
    }
  }

  Widget _buildTaskCard(Color indicatorColor, Map<String, dynamic> recordData) {
    // Extract data from the record
    final String recordId =
        recordData['Work_Id__c'] ?? recordData['recordId'] ?? 'Unknown';
    final String recordType = recordData['RecordTypeName'] ??
        recordData['recordType'] ??
        widget.title;

    // Check if this record is completed
    final String status = recordData['status'] ?? 'Pending';
    final bool isCompleted = status == 'Complete' || status == 'Completed';

    // Use other fields from the real API response
    final String date = recordData['date'] ??
        '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}';
    // final String villageName = recordData['Village_Name__c'] ?? 'N/A';

    return InkWell(
      // onTap: isCompleted
      //     ? () => _showRecordDetails(
      //         recordData) // Only show details for completed records
      //     : () => _openForm(
      //         widget.title, recordData['Id'] ?? recordData['recordId']),
      onTap: isCompleted
          ? () => _showRecordDetails(recordData)
          : () => _openForm(
              widget.title,
              recordData['Work_Id__c'] ?? recordData['recordId'],
              recordData['Id']),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isCompleted
              ? Colors.grey.shade100
              : Colors.white, // Slightly gray background for completed items
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
                width: 5, color: isCompleted ? Colors.green : indicatorColor),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 6,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(recordType,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Work ID: $recordId'),
                      Text('DATE: $date'),
                      //if (villageName != 'N/A') Text('Village: $villageName'),
                    ],
                  ),
                ),
                // if (!isCompleted) // Only show menu button for non-completed records
                //   PopupMenuButton<String>(
                //     icon: const Icon(Icons.more_vert),
                //     onSelected: (value) => _handleMenuAction(value, recordData),
                //     itemBuilder: (context) => [
                //       const PopupMenuItem(
                //         value: 'details',
                //         child: Text('View Details'),
                //       ),
                //       const PopupMenuItem(
                //         value: 'complete',
                //         child: Text('Mark as Complete'),
                //       ),
                //       const PopupMenuItem(
                //         value: 'approve',
                //         child: Text('Submit for Approval'),
                //       ),
                //     ],
                //   ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 18.0),
              child: Text(
                'Status: ${isCompleted ? 'Completed' : 'Pending'}',
                style: TextStyle(
                  color: isCompleted ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(String action, Map<String, dynamic> recordData) {
    switch (action) {
      case 'details':
        _showRecordDetails(recordData);
        break;
      case 'complete':
        _updateRecordStatus(recordData, 'Complete');
        break;
      case 'approve':
        _updateRecordStatus(recordData, 'Approved');
        break;
    }
  }

  void _updateRecordStatus(Map<String, dynamic> recordData, String newStatus) {
    // Find the record in storedIds and update its status
    if (storedIds is List) {
      for (int i = 0; i < storedIds.length; i++) {
        if (storedIds[i]['recordId'] == recordData['recordId']) {
          setState(() {
            storedIds[i]['status'] = newStatus;
          });

          // Save the updated data back to Hive
          box.put('ids', storedIds);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Record status updated to $newStatus')),
          );
          break;
        }
      }
    }
  }

  void _showRecordDetails(Map<String, dynamic> recordData) {
    // Filter out null values and convert to a more readable format
    final Map<String, dynamic> displayData = {};
    recordData.forEach((key, value) {
      if (value != null && key != 'attributes') {
        displayData[key] = value;
      }
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Record Details'),
        content: Container(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Display the Record Type and ID first
                Text('Type: ${displayData['RecordTypeName'] ?? widget.title}',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('ID: ${displayData['Work_Id__c'] ?? 'Unknown'}',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Status: Completed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    )),
                const SizedBox(height: 8),
                Text(
                    'Submission Time: ${DateTime.now().toString().substring(0, 19)}',
                    style: TextStyle(fontStyle: FontStyle.italic)),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

// Helper method to format field names for display
  // Method removed as it was unused

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          // Use flexible height calculation based on device size
          toolbarHeight:
              MediaQuery.of(context).size.height * 0.08, // 8% of screen height
          elevation: 0,
          titleSpacing: 0,
          title: LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;
              final isSmallScreen = screenWidth < 360;

              // Calculate available width for title (minus icon widths and padding)
              final availableWidth = screenWidth -
                  (screenWidth *
                      0.25); // Approximate space for icons and padding

              // Calculate font size based on title length
              double fontSize = isSmallScreen ? 14 : 16;
              if (widget.title.length > 15) {
                fontSize = isSmallScreen ? 12 : 14;
              }
              if (widget.title.length > 25) {
                fontSize = isSmallScreen ? 10 : 12;
              }

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.02),
                child: Row(
                  children: [
                    // Remove Flexible to prevent constraining the text width
                    Container(
                      constraints: BoxConstraints(maxWidth: availableWidth),
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          // Remove overflow ellipsis to show complete text
                        ),
                        softWrap: true,
                        maxLines: 2, // Allow up to 2 lines for longer titles
                      ),
                    ),
                    SizedBox(width: screenWidth * 0.01),
                    IconButton(
                      iconSize: isSmallScreen ? 18 : 20,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(
                        minWidth: screenWidth * 0.08,
                        minHeight: screenWidth * 0.08,
                      ),
                      icon: const Icon(Icons.arrow_downward_rounded,
                          color: Colors.black),
                      onPressed: () async {
                        final selectedRecordType =
                            await showModalBottomSheet<String>(
                          context: context,
                          builder: (context) {
                            return FormListBottomSheet(
                              onRecordTypeSelected: (recordType) {
                                Navigator.pop(context, recordType);
                              },
                            );
                          },
                        );

                        if (selectedRecordType != null &&
                            selectedRecordType != widget.title) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => Workid(
                                title: selectedRecordType,
                                recordType: selectedRecordType,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    const Spacer(),
                    IconButton(
                      iconSize: isSmallScreen ? 18 : 20,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(
                        minWidth: screenWidth * 0.08,
                        minHeight: screenWidth * 0.08,
                      ),
                      icon: const Icon(Icons.refresh, color: Colors.black),
                      onPressed: () {
                        setState(() {
                          isLoading = true;
                        });
                        _initHiveBox();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          backgroundColor: Colors.white,
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(kToolbarHeight),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return TabBar(
                  isScrollable: true,
                  padding: EdgeInsets.symmetric(
                    vertical: MediaQuery.of(context).size.height * 0.01,
                    horizontal: MediaQuery.of(context).size.width * 0.02,
                  ),
                  labelStyle: TextStyle(
                    fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [
                    Tab(child: Text('All')),
                    Tab(child: Text('Pending')),
                    Tab(child: Text('Complete')),
                  ],
                );
              },
            ),
          ),
        ),
        drawer: CustomDrawer(username: widget.username),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: List.generate(3, (tabIndex) {
                  // If we have real record data loaded, use it
                  if (storedIds != null) {
                    //List<dynamic> recordList;
                    List<dynamic> recordList =
                        storedIds is List ? storedIds : [];
                    // Ensure storedIds is a List
                    if (storedIds is List) {
                      recordList = storedIds;
                    } else if (storedIds is Map) {
                      // If it's a Map, try to extract records
                      recordList = storedIds['records'] ?? [];
                    } else {
                      // If not a supported type, create an empty list
                      recordList = [];
                    }

                    // Convert each record to Map if needed
                    final List<Map<String, dynamic>> records =
                        recordList.map<Map<String, dynamic>>((record) {
                      if (record is Map) {
                        return Map<String, dynamic>.from(record);
                      } else {
                        // If record is not a map, create a simple map with default values
                        return {
                          'Id': record.toString(),
                          'RecordTypeName': widget.title,
                          'Disbursement_status__c': 'Pending',
                        };
                      }
                    }).toList();

                    // Define a function to get the status based on record fields
                    String getStatus(Map<String, dynamic> record) {
                      return record['status'] ?? 'Pending';
                    }

                    // Filter based on tab index
                    List<Map<String, dynamic>> filteredRecords = [];
                    switch (tabIndex) {
                      case 0: // All
                        filteredRecords =
                            List<Map<String, dynamic>>.from(records);
                        break;
                      case 1: // Pending
                        filteredRecords = records
                            .where((record) => getStatus(record) == 'Pending')
                            .toList();
                        break;
                      case 2: // Complete
                        filteredRecords = records
                            .where((record) => getStatus(record) == 'Complete')
                            .toList();
                        break;
                      // case 3: // Approval/Approved
                      //   filteredRecords = records
                      //       .where((record) =>
                      //           getStatus(record) == 'Approved' ||
                      //           getStatus(record) == 'Approval')
                      //       .toList();
                      //   break;
                      // case 4: // Rejected
                      //   filteredRecords = records
                      //       .where((record) => getStatus(record) == 'Rejected')
                      //       .toList();
                      //   break;
                    }

                    return filteredRecords.isEmpty
                        ? const Center(child: Text('No records found'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredRecords.length,
                            itemBuilder: (context, index) {
                              return _buildTaskCard(
                                cardColors[index % cardColors.length],
                                filteredRecords[index],
                              );
                            },
                          );
                  } else {
                    return const Center(child: Text('No data available'));
                  }
                }),
              ),
        // bottomNavigationBar: CustomBottomNavBar(
        //   currentIndex: selectedTab,
        //   onTap: (index) {
        //     setState(() {
        //       selectedTab = index;
        //     });
        //   },
        // ),
      ),
    );
  }

// Helper to ensure schema data exists for this record type
  Future<void> _ensureSchemaForRecordType(String recordType) async {
    try {
      final schemaData = await LocalJsonStorage.readResponse('schema');
      bool needsToFetchSchema = false;

      if (schemaData == null) {
        needsToFetchSchema = true;
      } else if (schemaData is Map && schemaData.containsKey('recordTypes')) {
        // If schema is organized, check if this record type exists
        if (!schemaData['recordTypes'].containsKey(recordType)) {
          needsToFetchSchema = true;
        }
      } else if (schemaData is List) {
        // If schema is a flat list, check if any field has this record type
        bool hasFieldsForType = schemaData
            .any((field) => field is Map && field['recordType'] == recordType);
        if (!hasFieldsForType) {
          needsToFetchSchema = true;
        }
      }

      if (needsToFetchSchema) {
        final ApiCall apiCall = ApiCall();
        final normalizedRecordType = replaceSpacesWithUnderscores(recordType);
        final result = await apiCall.callApi(
            endpoint: 'schema', title: normalizedRecordType);

        if (result['success']) {
        } else {
          // Failed to fetch schema
        }
      }
    } catch (e) {
      // Error ensuring schema
    }
  }

// Helper to save schema fields organized by record type
  Future<void> _saveSchemaFields(
      List<dynamic> fields, String recordType) async {
    try {
      // Load existing schema data or create new structure
      final existing =
          await LocalJsonStorage.readResponse('schema') ?? {'recordTypes': {}};
      Map<String, dynamic> schemaData;

      if (existing is List) {
        // Convert flat list to organized structure
        schemaData = {'recordTypes': {}, 'fields': existing};
      } else if (existing is Map) {
        schemaData = Map<String, dynamic>.from(existing);
        if (!schemaData.containsKey('recordTypes')) {
          schemaData['recordTypes'] = {};
        }
      } else {
        schemaData = {'recordTypes': {}};
      }

      // Save these fields under this record type
      schemaData['recordTypes'][recordType] = fields;

      // Save back to JSON file
      await LocalJsonStorage.saveResponse('schema', schemaData);
    } catch (e) {
      // Error saving schema fields
    }
  }
}
