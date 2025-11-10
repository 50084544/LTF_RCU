import 'package:sachet/core/constants/constants.dart';
import 'package:sachet/core/network/api_service.dart';
import 'package:sachet/features/form/data/datasources/form_service.dart';
import 'package:flutter/material.dart';
import '../../data/models/form_model.dart';
import 'package:hive/hive.dart';
import 'dart:convert';
import 'package:lottie/lottie.dart';
import 'package:sachet/core/network/LocalJsonStorage.dart';
import '../widgets/fileupload.dart';

class DynamicFormScreen extends StatefulWidget {
  final String? recordId;
  final String? recordType;
  final String? uid;
  final String? username;

  final Future<dynamic> Function()? schemaLoader;
  const DynamicFormScreen({
    this.recordId,
    this.recordType,
    this.uid,
    this.username,
    this.schemaLoader,
    Key? key,
  }) : super(key: key);

  @override
  State<DynamicFormScreen> createState() => _DynamicFormScreenState();
}

class _DynamicFormScreenState extends State<DynamicFormScreen> {
  final _formKey = GlobalKey<FormState>();
  List<FormModel> formFields = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  // Keep track of the last disbursal status to detect changes
  // Global key to access the FileUploadSection state
  final _fileUploadKey = GlobalKey<FileUploadSectionState>();
  String? _lastDisbursalStatus;
  // Form content key for forcing rebuilds
  late ValueKey<String> formContentKey;

  @override
  void initState() {
    super.initState();
    formContentKey =
        ValueKey('form_content_${DateTime.now().millisecondsSinceEpoch}');
    loadFormData();
  }

  @override
  void didUpdateWidget(DynamicFormScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if we need to rebuild the form due to disbursal status changes
    checkForDisbursalStatusChanges();
  }

  // Check if disbursal status changed and rebuild form if needed
  void checkForDisbursalStatusChanges() {
    // Find the current disbursal status in the form fields
    String? currentDisbursalStatus = FormModel.disbursalStatus;

    // Also check the actual form fields
    for (var field in formFields) {
      if (field.apiName == 'Disbursal_Status__c') {
        currentDisbursalStatus = field.value;
        break;
      }
    }

    if (currentDisbursalStatus != _lastDisbursalStatus) {
      _lastDisbursalStatus = currentDisbursalStatus;

      // Update all form fields
      if (currentDisbursalStatus != null &&
          widget.recordType == 'Live_Disbursement') {
        FormModel.updateLiveDisbursalStatus(
            currentDisbursalStatus, context, _formKey);
      }

      // Force a rebuild of the form to reflect editability changes
      setState(() {
        // Generate a new key to force a complete rebuild
        formContentKey =
            ValueKey('form_content_${DateTime.now().millisecondsSinceEpoch}');
      });
    }
  }

  Future<void> loadFormData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Load schema fields first
      List<FormModel> schemaFields = await _loadSchemaFields();

      // Load record data if recordId and recordType are provided
      Map<String, dynamic>? recordData;
      if (widget.recordId != null && widget.recordType != null) {
        recordData = await _loadRecordData();
      }

      // Combine schema fields with record data
      List<FormModel> fields =
          await _combineFieldsAndRecordData(schemaFields, recordData);

      // Set the fields in the FormModel's static variable for access from any form field
      // FormModel.setFormFields(fields);

      FormModel.setFormFields(fields, context, _formKey);

      // Check for Disbursal Status field and update initial state
      for (var field in fields) {
        if (field.apiName == 'Disbursal_Status__c' &&
            widget.recordType == 'Live_Disbursement') {
          _lastDisbursalStatus = field.value;
          if (field.value != null) {
            FormModel.updateLiveDisbursalStatus(field.value, context, _formKey);
          }
          break;
        }
      }

      setState(() {
        formFields = fields;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading form: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<List<FormModel>> _loadSchemaFields() async {
    // Try using the provided schema loader if available
    if (widget.schemaLoader != null) {
      try {
        final schemaData = await widget.schemaLoader!();
        if (schemaData != null) {
          if (schemaData is List) {
            return schemaData
                .map((item) =>
                    FormModel.fromJson(Map<String, dynamic>.from(item)))
                .toList();
          }
        }
      } catch (e) {}
    }

    // Fall back to loading directly from Hive
    return await _loadFieldsDirectly();
  }

  Future<List<FormModel>> _combineFieldsAndRecordData(
      List<FormModel> schemaFields, Map<String, dynamic>? recordData) async {
    List<FormModel> result = List.from(schemaFields);

    if (recordData == null || recordData.isEmpty) {
      return result;
    }

    if (recordData['RecordTypeName'] == 'PDAV') {
      // Define a list of fields that should be non-mandatory
      final nonMandatoryFields = [
        'Does_asset_make_model_match_with_system__c',
        'Does_Asset_Registration_number_match__c',
        'Do_the_details_in_INVOICE_matches__c',
        'Insurance_Certificate_received__c',
        'Confirm_Asset_Make_Model__c',
        'If_No_Match_mention_the_mismatched__c',
        'RC_received__c',
        'If_yes_please_share_RC_number__c',
        'If_No_mention_the_reason__c'
      ];

      final mandatoryFields = [
        'Is_customer_contactable_on_phone__c',
        'Loan_Taken_Yes_No__c',
        'Is_the_customer_s_address_traceable__c',
        'At_time_of_visit_met_with__c',
        'Is_the_Asset_seen_at_the_time_of_visit__c',
        'Is_the_loan_taken_for_self_Yes_No__c',
        'Local_or_OGL_Pick__c'
      ];

      // Loop through fields and make non-mandatory if in the list
      for (var field in result) {
        if (nonMandatoryFields.contains(field.apiName) && field.editable) {
          // Keep the field editable but make it non-mandatory
          field.isRequired = false;
        } else if (field.editable) {
          // All other fields remain mandatory
          field.isRequired = true;
        }
        // } else if (mandatoryFields.contains(field.apiName) && field.editable) {
        //   // Ensure the field is mandatory
        //   field.isRequired = true;
        //   print('Ensured ${field.apiName} is mandatory');
        // }
      }
    }

    // for (var field in result) {
    //   if (field.apiName.isNotEmpty &&
    //       recordData.containsKey(field.apiName) &&
    //       field.pageType == 'List') {
    //     field.value = recordData[field.apiName]?.toString();
    //   }
    // }

    // Set record type on all fields first
    bool isGoldLoanRecordType = recordData['RecordTypeName'] == 'Gold_Loan';
    // print('Is Gold Loan Record Type: $isGoldLoanRecordType');

    if (isGoldLoanRecordType) {
      // print('Gold Loan Record Data Keys: ${recordData.keys.toList()}');
      // print('Work_Id__c value: ${recordData['Work_Id__c']}');

      // First pass: Set record type for all fields
      for (var field in result) {
        field.recordType = 'Gold_Loan';
      }

      // Second pass: Set values for all fields
      for (var field in result) {
        if (field.apiName.isNotEmpty && recordData.containsKey(field.apiName)) {
          // print(
          //     'Setting value for field: ${field.apiName} = ${recordData[field.apiName]}');
          field.value = recordData[field.apiName]?.toString();
        }
      }

      // Check Status_by_RM__c field and update TM/ZM visibility
      if (recordData.containsKey('Status_by_RM__c')) {
        String? statusByRM = recordData['Status_by_RM__c']?.toString();
        // print('Status_by_RM__c value: $statusByRM');

        if (statusByRM == 'Assigned to TM') {
          //print('Enabling TM fields for Gold Loan');
          //FormModel.updateGOLD_LOAN_RPM_TMVisibility('TM');

          final ZM_Fields = [
            'GeneralZMRemark1__c',
            'GeneralZMRemark2__c',
            'GeneralZMRemark3__c',
            'GeneralZMRemark4__c',
            'GeneralZMRemark5__c',
            'RBIGuidelinesZMRemark1__c',
            'RBIGuidelinesZMRemark2__c',
            'RBIGuidelinesZMRemark3__c',
            'RBIGuidelinesZMRemark4__c',
            'OperatinalGuidelinesZMRemark1__c',
            'OperatinalGuidelinesZMRemark2__c',
            'OperatinalGuidelinesZMRemark3__c',
            'OperatinalGuidelinesZMRemark4__c',
            'OperatinalGuidelinesZMRemark5__c',
            'OperatinalGuidelinesZMRemark6__c',
            'OperatinalGuidelinesZMRemark7__c',
            'OperatinalGuidelinesZMRemark8__c',
            'OperatinalGuidelinesZMRemark9__c',
            'OperatinalGuidelinesZMRemark10__c',
            'OperatinalGuidelinesZMRemark11__c',
            'OperatinalGuidelinesZMRemark12__c',
            'OperatinalGuidelinesZMRemark13__c',
            'ComplianceTrainingZMRemark2__c',
            'ComplianceTrainingZMRemark3__c',
            'ComplianceTrainingZMRemark4__c',
            'Other_ZM_Observations_Please_mention_a__c',
            'ATR_ZM_Remark_Please_mention_open_AT__c',
            'OperatinalGuidelinesZMRemark14__c',
            'OperatinalGuidelinesZMRemark15__c',
            'OperatinalGuidelinesZMRemark16__c',
            'OperatinalGuidelinesZMRemark17__c',
            'OperatinalGuidelinesZMRemark18__c',
            'OperatinalGuidelinesZMRemark19__c',
            'OperatinalGuidelinesZMRemark20__c',
            'GoldCheckingZMRemark1__c',
            'GoldCheckingZMRemark2__c',
            'GoldCheckingZMRemark3__c',
            'GoldCheckingZMRemark4__c',
            'GoldCheckingZMRemark5__c',
            'SecurityAndRiskManagementZM1__c',
            'SecurityAndRiskManagementZM2__c',
            'SecurityAndRiskManagementZM3__c',
            'SecurityAndRiskManagementZM4__c',
            'SecurityAndRiskManagementZM5__c',
            'SecurityAndRiskManagementZM6__c',
            'SecurityAndRiskManagementZM7__c',
            'SecurityAndRiskManagementZM8__c',
            'SecurityAndRiskManagementZM9__c',
            'SecurityAndRiskManagementZM10__c',
            'SecurityAndRiskManagementZM11__c',
            'ComplianceTrainingZMRemark1__c',
          ];

          for (var field in result) {
            if (ZM_Fields.contains(field.apiName)) {
              field.editable = false;
              field.value = null;
              //
              // print('Forced ZM field to non-editable: ${field.apiName}');
            }
          }
        } else if (statusByRM == 'Assigned to ZM') {
          //print('Enabling ZM fields for Gold Loan');
          //FormModel.updateGOLD_LOAN_RPM_TMVisibility('ZM');

          final TM_Fields = [
            'GeneralTMRemark1__c',
            'GeneralTMRemark2__c',
            'GeneralTMRemark3__c',
            'GeneralTMRemark4__c',
            'GeneralTMRemark5__c',
            'RBIGuidelinesTMRemark1__c',
            'RBIGuidelinesTMRemark2__c',
            'RBIGuidelinesTMRemark3__c',
            'RBIGuidelinesTMRemark4__c',
            'OperatinalGuidelinesTMRemark1__c',
            'OperatinalGuidelinesTMRemark2__c',
            'OperatinalGuidelinesTMRemark3__c',
            'OperatinalGuidelinesTMRemark4__c',
            'OperatinalGuidelinesTMRemark5__c',
            'OperatinalGuidelinesTMRemark6__c',
            'OperatinalGuidelinesTMRemark7__c',
            'OperatinalGuidelinesTMRemark8__c',
            'OperatinalGuidelinesTMRemark9__c',
            'OperatinalGuidelinesTMRemark10__c',
            'OperatinalGuidelinesTMRemark11__c',
            'OperatinalGuidelinesTMRemark12__c',
            'OperatinalGuidelinesTMRemark13__c',
            'OperatinalGuidelinesTMRemark14__c',
            'ComplianceTrainingTMRemark3__c',
            'ComplianceTrainingTMRemark4__c',
            'Other_TM_Observations_Please_mention_a__c',
            'ATR_TM_Remark_Please_mention_open_AT__c',
            'OperatinalGuidelinesTMRemark15__c',
            'OperatinalGuidelinesTMRemark16__c',
            'OperatinalGuidelinesTMRemark17__c',
            'OperatinalGuidelinesTMRemark18__c',
            'OperatinalGuidelinesTMRemark19__c',
            'OperatinalGuidelinesTMRemark20__c',
            'GoldCheckingTMRemark1__c',
            'GoldCheckingTMRemark2__c',
            'GoldCheckingTMRemark3__c',
            'GoldCheckingTMRemark4__c',
            'GoldCheckingTMRemark5__c',
            'SecurityAndRiskManagementTM1__c',
            'SecurityAndRiskManagementTM2__c',
            'SecurityAndRiskManagementTM3__c',
            'SecurityAndRiskManagementTM4__c',
            'SecurityAndRiskManagementTM5__c',
            'SecurityAndRiskManagementTM6__c',
            'SecurityAndRiskManagementTM7__c',
            'SecurityAndRiskManagementTM8__c',
            'SecurityAndRiskManagementTM9__c',
            'SecurityAndRiskManagementTM10__c',
            'SecurityAndRiskManagementTM11__c',
            'ComplianceTrainingTMRemark1__c',
            'ComplianceTrainingTMRemark2__c',
          ];

          for (var field in result) {
            if (TM_Fields.contains(field.apiName)) {
              field.editable = false;
              field.value = null;
              // print('Forced TM field to non-editable: ${field.apiName}');
            }
          }
        }
      }

      // Third pass: Handle child fields visibility
      // First find and process all picklist fields with value "Yes"
      Map<String, bool> childVisibilityMap = {};

      // Phase 1: Identify all picklists with value "Yes" and mark them and their children for hiding
      for (var field in result) {
        if (field.type == 'Picklist' && field.value == 'Yes') {
          //print('Found picklist field with YES value: ${field.apiName}');

          // Mark the parent picklist itself for hiding when value is 'Yes'
          childVisibilityMap[field.apiName] = false;
          // print('Marked parent picklist ${field.apiName} to be hidden');

          final Map<String, dynamic> fieldData = field.toJson();
          if (fieldData.containsKey('child')) {
            // print(
            //     'DEBUG: Child data type for ${field.apiName}: ${fieldData['child'].runtimeType}');

            // Convert to list regardless of the original format
            List<dynamic> childFields = [];

            if (fieldData['child'] is List) {
              childFields = fieldData['child'];
              //  print('Child is already a List');
            } else if (fieldData['child'] is Map) {
              // If it's a Map, try to extract values as a list
              childFields = fieldData['child'].values.toList();
              // print(
              //     'Child was Map, converted to List with ${childFields.length} items');
            } else if (fieldData['child'] is String) {
              // If it's a String, try to parse as JSON
              try {
                var decodedChildren = jsonDecode(fieldData['child']);
                if (decodedChildren is List) {
                  childFields = decodedChildren;
                } else if (decodedChildren is Map) {
                  childFields = decodedChildren.values.toList();
                }
                // print(
                //     'Child was String, parsed to List with ${childFields.length} items');
              } catch (e) {
                print('ERROR parsing child as JSON: $e');
              }
            }

            // print(
            //     'Child fields to hide for ${field.apiName}: ${childFields.length} items');

            // Mark all child fields to be hidden
            for (var child in childFields) {
              if (child is FormModel) {
                String childApiName = child.apiName;
                childVisibilityMap[childApiName] = false;
                // print('Marked child ${childApiName} to be hidden');
              } else if (child is Map && child.containsKey('apiName')) {
                String childApiName = child['apiName'];
                childVisibilityMap[childApiName] = false;
                //  print('Marked child ${childApiName} (from map) to be hidden');
              } else if (child is String) {
                String childApiName = child;
                childVisibilityMap[childApiName] = false;
                // print(
                //     'Marked child ${childApiName} (from string) to be hidden');
              }
            }
          }
        }
      }

      // Phase 2: Apply visibility settings to all fields based on the map
      for (var field in result) {
        // Set values from record data if available
        if (field.apiName.isNotEmpty && recordData.containsKey(field.apiName)) {
          field.value = recordData[field.apiName]?.toString();
          // print('Set field value: ${field.apiName} = ${field.value}');
        }

        // Apply visibility rules based on the childVisibilityMap
        if (childVisibilityMap.containsKey(field.apiName)) {
          field.isVisible = childVisibilityMap[field.apiName]!;
          // print(
          //     'VISIBILITY UPDATE: Field ${field.apiName} isVisible set to ${field.isVisible}');

          // Double-check if this is a picklist with value "Yes"
          if (field.type == 'Picklist' && field.value == 'Yes') {
            // print(
            //     'Confirmed hiding picklist field with YES value: ${field.apiName}');
          }
        }

        // For picklist fields, make sure we handle any children they might have
        if (field.type == 'Picklist') {
          // If this is a picklist with "Yes" value, ensure its children are hidden
          if (field.value == 'Yes') {
            //  print('Processing picklist with YES value: ${field.apiName}');

            // Get any child fields this picklist might have
            final Map<String, dynamic> fieldData = field.toJson();

            if (fieldData.containsKey('child')) {
              //  print('Found child fields in picklist: ${field.apiName}');

              // Convert to list regardless of the original format
              List<dynamic> childFields = [];

              if (fieldData['child'] is List) {
                childFields = fieldData['child'];
              } else if (fieldData['child'] is Map) {
                // If it's a Map, try to extract values as a list
                childFields = fieldData['child'].values.toList();
              } else if (fieldData['child'] is String) {
                // If it's a String, try to parse as JSON
                try {
                  var decodedChildren = jsonDecode(fieldData['child']);
                  if (decodedChildren is List) {
                    childFields = decodedChildren;
                  } else if (decodedChildren is Map) {
                    childFields = decodedChildren.values.toList();
                  }
                } catch (e) {
                  print('ERROR parsing child as JSON: $e');
                }
              }

              bool showChildren =
                  false; // When field.value is 'Yes', we hide children

              // Process each child field
              for (var child in childFields) {
                if (child is FormModel) {
                  String childApiName = child.apiName;
                  // Find the actual field in our result list
                  for (var targetField in result) {
                    if (targetField.apiName == childApiName) {
                      targetField.isVisible = showChildren;
                      // print(
                      //     'DIRECT update: Setting child ${childApiName} isVisible=${showChildren}');
                      break;
                    }
                  }
                } else if (child is Map && child.containsKey('apiName')) {
                  String childApiName = child['apiName'];
                  // Find the actual field in our result list
                  for (var targetField in result) {
                    if (targetField.apiName == childApiName) {
                      targetField.isVisible = showChildren;
                      // print(
                      //     'DIRECT update: Setting child ${childApiName} isVisible=${showChildren}');
                      break;
                    }
                  }
                } else if (child is String) {
                  String childApiName = child;
                  // Find the actual field in our result list
                  for (var targetField in result) {
                    if (targetField.apiName == childApiName) {
                      targetField.isVisible = showChildren;
                      // print(
                      //     'DIRECT update: Setting child ${childApiName} isVisible=${showChildren}');
                      break;
                    }
                  }
                }
              }
            }
          } else if (field.value != 'Yes') {
            // If value is not 'Yes', make sure all child fields are visible
            final Map<String, dynamic> fieldData = field.toJson();

            if (fieldData.containsKey('child')) {
              List<dynamic> childFields = [];

              if (fieldData['child'] is List) {
                childFields = fieldData['child'];
              } else if (fieldData['child'] is Map) {
                childFields = fieldData['child'].values.toList();
              } else if (fieldData['child'] is String) {
                try {
                  var decodedChildren = jsonDecode(fieldData['child']);
                  if (decodedChildren is List) {
                    childFields = decodedChildren;
                  } else if (decodedChildren is Map) {
                    childFields = decodedChildren.values.toList();
                  }
                } catch (e) {}
              }

              bool showChildren =
                  true; // When field.value is not 'Yes', show children

              for (var child in childFields) {
                String? childApiName;

                if (child is FormModel) {
                  childApiName = child.apiName;
                } else if (child is Map && child.containsKey('apiName')) {
                  childApiName = child['apiName'];
                } else if (child is String) {
                  childApiName = child;
                }

                if (childApiName != null) {
                  // Find the actual field in our result list
                  for (var targetField in result) {
                    if (targetField.apiName == childApiName) {
                      targetField.isVisible = showChildren;
                      break;
                    }
                  }
                }
              }
            }
          }
        }
      }
    } else if (recordData['RecordTypeName'] == 'Branch_Compliance_Audit') {
      for (var field in result) {
        field.recordType = recordData['RecordTypeName'];

        if (field.apiName.isNotEmpty && recordData.containsKey(field.apiName)) {
          field.value = recordData[field.apiName]?.toString();
        }
      }

      String rpmPsIdValue = recordData['RPM_PS_ID__c']?.toString() ?? '';
      String tmPsNoValue = recordData['TM_PS_No__c']?.toString() ?? '';
      String statusByRM = recordData['Status_by_RM__c']?.toString() ?? '';

      if (rpmPsIdValue == widget.username) {
        for (var field in result) {
          field.editable = (field.apiName == 'RPM_Remark__c');
          // print('Field ${field.apiName} editable set to ${field.editable}');
        }
      } else if (tmPsNoValue == widget.username) {
        for (var field in result) {
          field.editable = (field.apiName == 'TM_Remark__c');
          // print('Field ${field.apiName} editable set to ${field.editable}');
        }
      } else if (statusByRM == 'Assigned to RCU Executive') {
        var fields = {'RPM_Remark__c', 'TM_Remark__c'};
        for (var fs in fields) {
          for (var field in result) {
            if (field.apiName == fs) {
              field.editable = false;
            }
          }
        }
      }
    } else {
      // Handle other record types normally
      for (var field in result) {
        field.recordType = recordData['RecordTypeName'];

        if (field.apiName.isNotEmpty && recordData.containsKey(field.apiName)) {
          field.value = recordData[field.apiName]?.toString();
        }
      }
    }

    return result;
  }

  // Add this method after _loadFieldsDirectly() to load record data

  Future<Map<String, dynamic>?> _loadRecordData() async {
    try {
      // Check if we have a recordId and recordType
      if (widget.recordId == null || widget.recordType == null) {
        return null;
      }

      // First try to find record in JSON storage

      // Check in records.json
      dynamic recordsData = await LocalJsonStorage.readResponse('records');
      Map<String, dynamic>? recordData;

      // Process records.json
      if (recordsData != null) {
        if (recordsData is Map) {
          // Try to get records for this record type
          final recordsForType = recordsData[widget.recordType];
          if (recordsForType is List) {
            // Search for record by ID
            for (var record in recordsForType) {
              if (record is Map && record['Work_Id__c'] == widget.recordId) {
                recordData = Map<String, dynamic>.from(record);
                break;
              }
            }
          }

          // If not found in specific record type, try all keys
          if (recordData == null) {
            for (var key in recordsData.keys) {
              final records = recordsData[key];
              if (records is List) {
                for (var record in records) {
                  if (record is Map &&
                      record['Work_Id__c'] == widget.recordId) {
                    recordData = Map<String, dynamic>.from(record);
                    break;
                  }
                }
              }
              if (recordData != null) break;
            }
          }
        } else if (recordsData is List) {
          // If records.json is a list, search directly
          for (var record in recordsData) {
            if (record is Map && record['Work_Id__c'] == widget.recordId) {
              recordData = Map<String, dynamic>.from(record);
              break;
            }
          }
        }
      }

      // If not found, check in all_records.json
      if (recordData == null) {
        dynamic allRecordsData =
            await LocalJsonStorage.readResponse('all_records');
        if (allRecordsData != null) {
          if (allRecordsData is Map && allRecordsData['records'] is List) {
            final List<dynamic> records = allRecordsData['records'];
            for (var record in records) {
              if (record is Map && record['Work_Id__c'] == widget.recordId) {
                recordData = Map<String, dynamic>.from(record);
                break;
              }
            }
          } else if (allRecordsData is List) {
            // If all_records.json is a list, search directly
            for (var record in allRecordsData) {
              if (record is Map && record['Work_Id__c'] == widget.recordId) {
                recordData = Map<String, dynamic>.from(record);
                break;
              }
            }
          }
        }
      }

      // If record found in JSON, return it
      if (recordData != null) {
        // Ensure the record has all required fields
        if (!recordData.containsKey('Work_Id__c')) {
          recordData['Work_Id__c'] = widget.recordId;
        }

        if (!recordData.containsKey('RecordTypeName')) {
          recordData['RecordTypeName'] = widget.recordType;
        }

        return recordData;
      }

      // If not found in JSON, fall back to Hive
      final recordsBox = await Hive.openBox('records');

      // Direct lookup by ID
      var data = recordsBox.get(widget.recordId);

      // Try alternate lookup methods if direct lookup fails
      if (data == null) {
        // Check in all_records
        final allRecords = recordsBox.get('all_records');
        if (allRecords != null && allRecords['records'] is List) {
          // Search for the record by ID in the records list
          for (var record in allRecords['records']) {
            if (record is Map && record['Work_Id__c'] == widget.recordId) {
              data = record;
              break;
            }
          }
        }

        // If still not found, check in each record type collection
        if (data == null && widget.recordType != null) {
          // Try to get records for the specific record type
          final recordsForType = recordsBox.get(widget.recordType);

          if (recordsForType is List) {
            for (var record in recordsForType) {
              if (record is Map && record['Work_Id__c'] == widget.recordId) {
                data = record;
                break;
              }
            }
          }
        }

        // Try all record types as a last resort
        if (data == null) {
          final recordTypes = recordsBox.get('record_types');
          if (recordTypes is List) {
            for (var recordType in recordTypes) {
              final typeRecords = recordsBox.get(recordType);
              if (typeRecords is List) {
                for (var record in typeRecords) {
                  if (record is Map &&
                      record['Work_Id__c'] == widget.recordId) {
                    data = record;
                    break;
                  }
                }
                if (data != null) break; // Exit loop if record is found
              }
            }
          }
        }
      } else {}

      // Process the found data
      if (data != null) {
        // Ensure recordData is a properly structured Map
        if (data is Map) {
          recordData = Map<String, dynamic>.from(data);

          // Make sure the record has all required fields
          if (!recordData.containsKey('Work_Id__c')) {
            recordData['Work_Id__c'] = widget.recordId;
          }

          if (!recordData.containsKey('RecordTypeName')) {
            recordData['RecordTypeName'] = widget.recordType;
          }
        } else if (data is List && data.isNotEmpty && data[0] is Map) {
          // If it's a list with map items, use the first one
          recordData = Map<String, dynamic>.from(data[0]);
        } else {
          // Last resort - create a minimal record structure
          recordData = {
            'Id': widget.recordId,
            'RecordTypeName': widget.recordType,
            'data': data.toString(),
          };
        }

        // Save this record to JSON for future reference
        try {
          final recordsJsonData =
              await LocalJsonStorage.readResponse('records') ?? {};
          Map<String, dynamic> recordsMap;

          if (recordsJsonData is List) {
            // Convert to map if it's a list
            recordsMap = {'records': recordsJsonData};
          } else if (recordsJsonData is Map) {
            recordsMap = Map<String, dynamic>.from(recordsJsonData);
          } else {
            recordsMap = {};
          }

          // Add this record type if it doesn't exist
          if (!recordsMap.containsKey(widget.recordType)) {
            recordsMap[widget.recordType!] = [];
          }

          // Add the record to its type collection if not already there
          List<dynamic> typeRecords = recordsMap[widget.recordType!];
          bool recordExists = false;

          for (int i = 0; i < typeRecords.length; i++) {
            if (typeRecords[i]['Work_Id__c'] == widget.recordId) {
              typeRecords[i] = recordData; // Update existing record
              recordExists = true;
              break;
            }
          }

          if (!recordExists) {
            typeRecords.add(recordData);
          }

          await LocalJsonStorage.saveResponse('records', recordsMap);
        } catch (e) {}

        return recordData;
      } else {
        // Create a default record
        return {
          "MC_Code__c": "Empty",
          "Any_relevant_Remarks__c": "",
          "Disbursement_status__c": "Pending",
          "RecordTypeName": widget.recordType ?? "Unknown",
          "Id": widget.recordId ?? "Unknown"
        };
      }
    } catch (e) {
      return null;
    }
  }

  // Directly access schema data, prioritizing JSON files over Hive
  Future<List<FormModel>> _loadFieldsDirectly() async {
    final List<FormModel> fields = [];

    try {
      // First try to load from LocalJsonStorage
      final schemaJsonData = await LocalJsonStorage.readResponse('schema');
      if (schemaJsonData != null) {
        if (schemaJsonData is List) {
          // Process list data directly
          for (var item in schemaJsonData) {
            if (item is Map) {
              try {
                fields.add(FormModel.fromJson(Map<String, dynamic>.from(item)));
              } catch (e) {}
            }
          }
        } else if (schemaJsonData is Map) {
          // If it's a map, look for fields array
          final fieldsList = schemaJsonData['fields'] ?? [];
          if (fieldsList is List) {
            for (var item in fieldsList) {
              if (item is Map) {
                try {
                  fields
                      .add(FormModel.fromJson(Map<String, dynamic>.from(item)));
                } catch (e) {}
              }
            }
          }
        }

        // If we found fields in the JSON file, return them
        if (fields.isNotEmpty) {
          return fields;
        }
      }

      // If JSON file is empty or not found, fall back to Hive
      final box = await Hive.openBox('schema');
      final dynamic schemaData = box.get('schema');

      if (schemaData != null) {
        if (schemaData is List) {
          // Process list data
          for (var item in schemaData) {
            if (item is Map) {
              try {
                fields.add(FormModel.fromJson(Map<String, dynamic>.from(item)));
              } catch (e) {}
            }
          }
        } else if (schemaData is Map) {
          // If it's a map, look for fields array
          final fieldsList = schemaData['fields'] ?? [];
          if (fieldsList is List) {
            for (var item in fieldsList) {
              if (item is Map) {
                try {
                  fields
                      .add(FormModel.fromJson(Map<String, dynamic>.from(item)));
                } catch (e) {}
              }
            }
          } else if (schemaData is String) {
            // Try parsing as JSON
            try {
              final decoded = jsonDecode(schemaData as String);
              if (decoded is List) {
                for (var item in decoded) {
                  if (item is Map) {
                    fields.add(
                        FormModel.fromJson(Map<String, dynamic>.from(item)));
                  }
                }
              } else if (decoded is Map && decoded['fields'] is List) {
                for (var item in decoded['fields']) {
                  if (item is Map) {
                    fields.add(
                        FormModel.fromJson(Map<String, dynamic>.from(item)));
                  }
                }
              }
            } catch (e) {}
          }
        }
      }

      // If we found fields in Hive, save them to JSON for next time
      if (fields.isNotEmpty) {
        try {
          await LocalJsonStorage.saveResponse(
              'schema', fields.map((f) => f.toJson()).toList());
        } catch (e) {}
      }
    } catch (e) {}

    return fields;
  }

  final _formApiService = FormApiService();
// Update the handleSubmit method to navigate back with a result
  // Add this method to show the success animation
  Future<void> _showSuccessAnimation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            height: 340,
            child: Stack(
              children: [
                // Main content
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 150,
                        height: 150,
                        child: Lottie.asset(
                          'assets/animations/successAnimation.json',
                          repeat: false,
                          animate: true,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Success!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Form submitted successfully',
                        style: TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                // Close icon at top right
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 28),
                    onPressed: () {
                      Navigator.of(context).pop(); // Close the dialog
                      // Future.delayed(Duration.zero, () {
                      //   if (mounted) {
                      //     Navigator.of(this.context).pop({
                      //       'success': true,
                      //       'recordId': widget.recordId,
                      //       'newStatus': 'Complete'
                      //     });
                      //   }
                      // }
                      // );
                    },
                    tooltip: 'Close',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      return Future.delayed(const Duration(milliseconds: 300));
    });
  }

  // Add this method to show the error animation
  Future<void> _showErrorAnimation() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            height: 350,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: Lottie.asset(
                    'assets/animations/failedAnimation.json',
                    repeat: false,
                    animate: true,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Failed to Submit Form',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper method to handle image uploads in the background
  Future<void> _uploadFilesInBackground() async {
    if (widget.recordType == 'Live_Disbursement' && widget.recordId != null) {
      // This is a fire-and-forget call - we don't wait for the result
      try {
        // Get the FileUploadSection instance
        if (_fileUploadKey.currentWidget != null) {
          // Access the state directly
          final fileUploadState = _fileUploadKey.currentState;

          if (fileUploadState != null) {
            // Trigger the upload process
            final uploadResult = await fileUploadState.uploadFiles();
          } else {}
        } else {}
      } catch (e) {
        // We intentionally don't handle errors here since this is a background operation
      }
    }
  }

  Future<void> handleSubmit() async {
    // Show confirmation dialog before submitting
    final shouldSubmit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: Colors.white,
          title: Center(
            child: Text(
              'Confirm Submission',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue[900],
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Are you sure you want to submit?',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[300],
                foregroundColor: Colors.black87,
                minimumSize: const Size(90, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: const Text('No'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(90, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (shouldSubmit != true) {
      // User cancelled, do nothing
      return;
    }

    // Existing submission logic
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isSubmitting = true;
      });

      try {
        final FormApiService apiService = FormApiService();

        // print('Submitting form with fields: ${widget.username}');
        final result = await apiService.submitForm(
          recordType: widget.recordType ?? '',
          formFields: formFields,
          recordId: widget.recordId,
          uid: widget.uid,
          username: widget.username,
        );

        if (result.containsKey('Success_Code') &&
            result['Success_Code'] == '1') {
          String recordId = result['Work_Id'];

          // Initiate image upload in background without waiting for it
          // This won't block the success flow
          _uploadFilesInBackground();

          // Show success animation dialog
          await _showSuccessAnimation();

          // Return to previous screen with the updated record ID and status
          if (mounted) {
            Navigator.pop(context, {
              'success': true,
              'recordId': recordId,
              'newStatus': 'Complete'
            });
          }
        } else {
          // Show error animation
          await _showErrorAnimation();
          setState(() {
            _isSubmitting = false;
          });
          // Do NOT pop here, stay on the form screen
        }
      } catch (e) {
        // Show error animation
        await _showErrorAnimation();

        setState(() {
          _isSubmitting = false;
        });
        // Do NOT pop here, stay on the form screen
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen while form data is being loaded
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Work ID ${widget.recordId ?? ''}',
              style: const TextStyle(fontSize: 14)),
        ),
        body: Container(
          color: Colors.white,
          child: Center(
            child: Column(
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
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text('Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: loadFormData,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // The formContentKey is now a class variable that changes when needed
    // This ensures the form rebuilds when field values or editability changes

    Widget formContent = Padding(
      key: formContentKey,
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Form fields
              ...formFields.map((field) => Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: field.getWidget(_formKey, context),
                  )),

              // Add file upload section for Live_Disbursement record type
              if (widget.recordType == 'Live_Disbursement' &&
                  widget.recordId != null) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 10),
                FileUploadSection(
                  key: _fileUploadKey,
                  workId: widget.recordId!,
                  maxFiles: 3,
                  // Disable uploads if "Not disbursed" is selected
                  enabled: !formFields.any((field) =>
                      field.apiName == 'Disbursal_Status__c' &&
                      field.value == 'Not disbursed'),
                ),
              ],

              const SizedBox(height: 20),
              ElevatedButton(
                  onPressed: _isSubmitting ? null : handleSubmit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor:
                        Colors.blue, // Use your app's primary color
                  ),
                  child: const Text(
                    'Submit',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text('Work ID ${widget.recordId ?? ''}')),
      body: formFields.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No form fields available'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: loadFormData,
                    child: const Text('Reload Form'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // Form content
                formContent,

                // Loading overlay when submitting
                if (_isSubmitting)
                  Container(
                    color: Colors.black.withOpacity(
                        0.5), // Slightly darker for better visibility
                    child: Center(
                      child: Column(
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
                            'Submitting form...', // Changed text to indicate submission
                            style: TextStyle(
                              fontSize: 18,
                              fontStyle: FontStyle.italic,
                              color: Colors
                                  .white, // White text for better visibility on dark background
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      backgroundColor: AppColors.background,
    );
  }

  Future<List<FormModel>> _loadFieldsFromSchema(
      String recordId, String recordType) async {
    final schemaBox = await Hive.openBox('schema');
    final currentRecordType = schemaBox.get('current_record_type');
    final schemaData = schemaBox.get('schema');

    // If the current schema doesn't match the requested record type, fetch fresh data
    if (currentRecordType != recordType.replaceAll(' ', '_')) {
      final apiCall = ApiCall();
      await apiCall.callSchemaApi(recordType: recordType);
      // Get the updated schema
      final updatedSchema = schemaBox.get('schema');
      return _processSchemaData(updatedSchema, recordId);
    }

    return _processSchemaData(schemaData, recordId);
  }

// Add this method to process schema data and return a list of FormModel
  List<FormModel> _processSchemaData(dynamic schemaData, String recordId) {
    final List<FormModel> fields = [];
    if (schemaData != null) {
      if (schemaData is List) {
        for (var item in schemaData) {
          if (item is Map) {
            try {
              fields.add(FormModel.fromJson(Map<String, dynamic>.from(item)));
            } catch (e) {}
          }
        }
      } else if (schemaData is String) {
        try {
          final decoded = jsonDecode(schemaData);
          if (decoded is List) {
            for (var item in decoded) {
              if (item is Map) {
                fields.add(FormModel.fromJson(Map<String, dynamic>.from(item)));
              }
            }
          }
        } catch (e) {}
      }
    }
    return fields;
  }
}
