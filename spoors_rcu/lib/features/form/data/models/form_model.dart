import 'package:sachet/core/network/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';

class FormModel {
  final String type;
  final String label;
  bool editable;
  final String apiName;
  final String pageType;
  String? _value;
  String? recordType;
  late bool isRequired;
  List<String>? picklistValues;
  List<String>? childValues;
  dynamic _childFields;
  bool isVisible = true;
  String? header;

  // Add new property to track if field is related to a reference field
  String? relatedReferenceField;
  bool isReferenceRelatedField = false;

  // Image-related properties
  File? _imageFile;
  Uint8List? _imageBytes;
  final ImagePicker _picker = ImagePicker();

  // Controllers
  TextEditingController? _controller;

  // Getter and setter for value to keep controller in sync
  String? get value => _value;

  set value(String? newValue) {
    _value = newValue;
    // Update controller if it exists
    if (_controller != null && _value != _controller!.text) {
      _controller!.text = _value ?? '';
    }
  }

  // Image getters
  File? get imageFile => _imageFile;
  Uint8List? get imageBytes => _imageBytes;

  // Base64 encoded image for API requests
  String? get base64Image {
    if (_imageBytes != null) {
      return base64Encode(_imageBytes!);
    }
    return null;
  }

  // Static list to store all form fields reference
  static List<FormModel>? _allFormFields;

  // Static variable to track loading state for reference API calls
  static bool isReferenceApiLoading = false;

  // Static variable to track Disbursal Status selection for Live_Disbursement
  static String? disbursalStatus;

  // Dispose the controller when the form field is no longer needed
  void dispose() {
    _controller?.dispose();
    _controller = null;
  }

  FormModel({
    required this.type,
    required this.label,
    required this.editable,
    required this.apiName,
    required this.pageType,
    String? value,
    this.recordType,
    this.isRequired = true,
    this.picklistValues,
    this.relatedReferenceField,
    this.isReferenceRelatedField = false,
  }) {
    this.value = value; // Use the setter
  }

  // Method to capture image from camera
  Future<bool> captureImage(BuildContext context) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80, // Reduced quality to keep file size smaller
      );

      if (photo != null) {
        _imageFile = File(photo.path);
        _imageBytes = await _imageFile!.readAsBytes();

        // Store file path in value for displaying in UI
        value = photo.path;

        return true;
      }
      return false;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture image: ${e.toString()}')),
      );
      return false;
    }
  }

  // Method to select image from gallery
  Future<bool> pickImageFromGallery(BuildContext context) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (photo != null) {
        _imageFile = File(photo.path);
        _imageBytes = await _imageFile!.readAsBytes();

        // Store file path in value for displaying in UI
        value = photo.path;

        return true;
      }
      return false;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: ${e.toString()}')),
      );
      return false;
    }
  }

  // Method to clear selected image
  void clearImage() {
    _imageFile = null;
    _imageBytes = null;
    value = null;
  }

  Map<String, dynamic> toJson() {
    final json = {
      'type': type,
      'label': label,
      'editable': editable,
      'apiName': apiName,
      'value': _value,
      'recordType': recordType,
      'isRequired': isRequired,
      'picklistValues': picklistValues,
    };

    // Add base64 image data if available
    if (_imageBytes != null) {
      json['imageData'] = base64Image;
    }

    return json;
  }

  // Static method to set all form fields for reference
  static void setFormFields(List<FormModel> fields,
      [BuildContext? context, GlobalKey<FormState>? formKey]) {
    _allFormFields = fields;

    // Initialize original field states to preserve schema integrity
    _originalFieldStates = {};
    for (var field in fields) {
      _originalFieldStates![field.apiName] = {
        'editable': field.editable,
        'isRequired': field.isRequired,
        'pageType': field.pageType,
        'recordType': field.recordType,
      };
    }

    // Check if Live_Disbursement form with Disbursal Status field exists
    _checkForDisbursalStatusField();

    // Check if PDAV form with asset visibility field exists
    _updatePDAVFieldsVisibility();

    // Check if Collection_Audit form with Status field exists
    _initCollectionAuditStatus();

    // Check if Cross_Audit form exists for date difference calculations
    if (context != null && formKey != null) {
      _initCrossAuditDateDifference(context, formKey);
    }
  }

  // Add this helper method to check Collection_Audit status on initialization
  static void _initCollectionAuditStatus() {
    if (_allFormFields == null) return;

    FormModel? statusField;
    FormModel? loanRelationshipField;

    // Find the Status field in Collection_Audit and Loan Relationship field in PDAV
    for (var field in _allFormFields!) {
      // Check Collection_Audit record type for status field
      if (field.recordType == 'Collection_Audit' &&
          field.apiName == 'Status__c') {
        statusField = field;
      }
      // Check PDAV record type for loan relationship field
      else if (field.recordType == 'PDAV' &&
          field.apiName == 'Is_the_loan_taken_for_self_Yes_No__c') {
        loanRelationshipField = field;
      }

      // If we found both fields, we can stop searching
      if (statusField != null && loanRelationshipField != null) {
        break;
      }
    }

    // If we found the status field and it has a value, apply the rules
    if (statusField != null && statusField.value != null) {
      List<String> nonRequiredIfVisited = [
        'If_not_visited__c',
        'Approval_taken_for_on_behalf_collection__c'
      ];

      // Update field requirements based on status
      for (var field in _allFormFields!) {
        if (field.recordType == 'Collection_Audit' &&
            nonRequiredIfVisited.contains(field.apiName)) {
          //field.isRequired = (statusField.value != 'Visited');
          field.editable = (statusField.value != 'Visited');
        }
      }
    }

    // If we found the loan relationship field and it has a value, apply the rules
    if (loanRelationshipField != null && loanRelationshipField.value != null) {
      FormModel? relativeDetailsField;
      FormModel? thirdPartyDetailsField;

      // Find the two related fields that need to be toggled
      for (var field in _allFormFields!) {
        // Only look in PDAV record type
        if (field.recordType != 'PDAV') continue;

        if (field.apiName == 'If_Relative_mention_details__c') {
          relativeDetailsField = field;
        } else if (field.apiName == 'If_third_party_take_details__c') {
          thirdPartyDetailsField = field;
        }

        // If we found both fields, we can stop searching
        if (relativeDetailsField != null && thirdPartyDetailsField != null) {
          break;
        }
      }

      // Update the fields based on the selected value
      if (relativeDetailsField != null && thirdPartyDetailsField != null) {
        String relationshipValue = loanRelationshipField.value!;
        // print(
        //     'Initializing PDAV fields with loan relationship value: $relationshipValue');

        if (relationshipValue == 'Relative') {
          // If "Relative" is selected, enable relative details field and disable third party details
          relativeDetailsField.editable = true;
          thirdPartyDetailsField.editable = false;
          // Clear the third party field value since it's now disabled
          thirdPartyDetailsField.value = null;
        } else if (relationshipValue == 'Third Party') {
          // If "Third Party" is selected, enable third party details field and disable relative details
          relativeDetailsField.editable = false;
          thirdPartyDetailsField.editable = true;
          // Clear the relative field value since it's now disabled
          relativeDetailsField.value = null;
        } else {
          // For any other selection (like "Self" or null), disable both fields
          relativeDetailsField.editable = false;
          thirdPartyDetailsField.editable = false;
          // Clear both field values
          relativeDetailsField.value = null;
          thirdPartyDetailsField.value = null;
        }
      }
    }
  }

  // static void updateLiveDisbursalStatus(
  //     String? newStatus, BuildContext context, GlobalKey<FormState> formKey) {
  //   if (disbursalStatus == newStatus) return;

  //   disbursalStatus = newStatus;

  //   if (_allFormFields == null) return;

  //   bool foundDisbursalStatusField = false;
  //   bool makeReadOnly = disbursalStatus == 'Not disbursed';
  //   bool isDisbursed = disbursalStatus == 'Disbursed';

  //   // Process fields after Disbursal Status field
  //   for (var field in _allFormFields!) {
  //     // Once we find the Disbursal Status field, mark it so we know to process subsequent fields
  //     if (field.apiName == 'Disbursal_Status__c') {
  //       foundDisbursalStatusField = true;
  //       continue; // Skip this field itself
  //     }

  //     // Special handling for If_others_then__c and If_not_disbursed__c fields
  //     if (field.apiName == 'If_others_then__c' ||
  //         field.apiName == 'If_not_disbursed__c') {
  //       // Disable these fields if 'Disbursed' is selected
  //       if (isDisbursed) {
  //         field.editable = false;
  //         field.isRequired = false; // Also make them not required
  //         field.value = ''; // Clear their values
  //       } else if (makeReadOnly) {
  //         // For "Not disbursed", keep these fields editable
  //         field.editable = true;
  //         field.isRequired = true; // Make them required
  //       } else {
  //         // For any other status (e.g. "Others"), keep these fields editable
  //         field.editable = true;
  //         field.isRequired = false;
  //       }
  //       continue; // Skip further processing for these special fields
  //     }

  //     // Special handling for Status__c field - always keep editable
  //     if (field.apiName == 'Status__c') {
  //       // Skip making Status__c read-only, keep it editable regardless of disbursal status
  //       continue;
  //     }

  //     // Make all other fields after the Disbursal Status field read-only if "Not disbursed" is selected
  //     if (foundDisbursalStatusField) {
  //       field.editable =
  //           makeReadOnly ? false : (field.isRequired || field.editable);
  //     }
  //   }

  //   // Print debug information
  //   print('Disbursal status updated to: $disbursalStatus');
  //   print(
  //       'Fields updated based on disbursal status (Status__c remains editable)');

  //   // Refresh UI to show updated requirements
  //   if (context.mounted) {
  //     WidgetsBinding.instance.addPostFrameCallback((_) {
  //       try {
  //         if (context is Element) {
  //           // Mark this element for rebuild
  //           context.markNeedsBuild();

  //           // Also mark ancestors for rebuild to ensure the entire form updates
  //           context.visitAncestorElements((ancestor) {
  //             ancestor.markNeedsBuild();
  //             return true;
  //           });
  //         }

  //         // Force a frame to be scheduled
  //         WidgetsBinding.instance.scheduleFrame();

  //         // For really stubborn UI updates, use this more aggressive approach
  //         if (formKey.currentState != null) {
  //           Future.microtask(() {
  //             if (formKey.currentContext != null) {
  //               (formKey.currentContext as Element).markNeedsBuild();
  //             }
  //           });
  //         }
  //       } catch (e) {
  //         print('Error updating UI after Collection Audit status change: $e');
  //       }
  //     });
  //   }
  // }

  // Store original field states for all fields to preserve schema integrity
  static Map<String, Map<String, dynamic>>? _originalFieldStates;

  // Helper method to check if a field can be modified based on original schema
  static bool _canModifyField(FormModel field) {
    Map<String, dynamic>? originalState = _originalFieldStates?[field.apiName];
    bool wasOriginallyEditable = originalState?['editable'] ?? false;
    String fieldPageType = originalState?['pageType'] ?? '';

    // Only modify fields that were originally editable and have pageType "Form"
    return wasOriginallyEditable && fieldPageType == 'Form';
  }

  static void updateLiveDisbursalStatus(
      String? newStatus, BuildContext context, GlobalKey<FormState> formKey) {
    if (disbursalStatus == newStatus) return;

    disbursalStatus = newStatus;

    if (_allFormFields == null) return;

    // Store original field states on first call - capture all fields regardless of current editable state
    if (_originalFieldStates == null) {
      _originalFieldStates = {};
      for (var field in _allFormFields!) {
        _originalFieldStates![field.apiName] = {
          'editable': field.editable,
          'isRequired': field.isRequired,
          'pageType': field.pageType,
          'recordType': field.recordType,
        };
      }
    }

    bool isDisbursed = disbursalStatus == 'Disbursed';
    bool isNotDisbursed = disbursalStatus == 'Not disbursed';

    // Find the index of If_others_then__c field to determine which fields come after it
    int ifOthersThenIndex = -1;
    for (int i = 0; i < _allFormFields!.length; i++) {
      if (_allFormFields![i].recordType == 'Live_Disbursement' &&
          _allFormFields![i].apiName == 'If_others_then__c') {
        ifOthersThenIndex = i;
        break;
      }
    }

    // Process all fields in the Live_Disbursement form
    for (int i = 0; i < _allFormFields!.length; i++) {
      var field = _allFormFields![i];

      // Skip if not a Live_Disbursement field
      if (field.recordType != 'Live_Disbursement') continue;

      // Skip fields that cannot be modified based on original schema
      if (!_canModifyField(field)) {
        continue;
      }

      // Skip the Disbursal_Status__c field itself - always keep editable if originally editable
      if (field.apiName == 'Disbursal_Status__c') {
        continue;
      }

      // Special handling for If_not_disbursed__c field
      if (field.apiName == 'If_not_disbursed__c') {
        if (isDisbursed) {
          // Disable if Disbursed is selected
          field.editable = false;
          field.isRequired = false;
          field.value = '';
          if (field._controller != null) {
            field._controller!.text = '';
          }
        } else if (isNotDisbursed) {
          // Enable if Not disbursed is selected
          field.editable = true;
          field.isRequired = true;
        } else {
          // For any other status, keep it editable
          field.editable = true;
          field.isRequired = false;
        }
        // print(
        //     'Updated If_not_disbursed__c: Editable = ${field.editable}, Required = ${field.isRequired}');
        continue;
      }

      // Special handling for If_others_then__c field
      if (field.apiName == 'If_others_then__c') {
        if (isDisbursed) {
          // Disable if Disbursed is selected
          field.editable = false;
          field.isRequired = false;
          field.value = '';
          if (field._controller != null) {
            field._controller!.text = '';
          }
        } else {
          // Keep disabled by default - will be enabled by updateNotDisbursedReason if 'others' is selected
          field.editable = false;
          field.isRequired = false;
        }
        // print(
        //     'Updated If_others_then__c: Editable = ${field.editable}, Required = ${field.isRequired}');
        continue;
      }

      // For all fields that come AFTER If_others_then__c
      if (ifOthersThenIndex != -1 && i > ifOthersThenIndex) {
        if (isNotDisbursed) {
          // If "Not disbursed" is selected, disable only fields after If_others_then__c
          field.editable = false;
          field.isRequired = false;
          // Clear values of disabled fields
          if (field.value != null) {
            field.value = '';
            if (field._controller != null) {
              field._controller!.text = '';
            }
          }
          // print('Disabled field after If_others_then__c: ${field.apiName}');
        } else if (isDisbursed) {
          // If "Disbursed" is selected, restore original editable and required state for fields after If_others_then__c
          Map<String, dynamic>? originalState =
              _originalFieldStates?[field.apiName];
          bool originalEditable = originalState?['editable'] ?? false;
          bool originalRequired = originalState?['isRequired'] ?? false;
          field.editable = originalEditable;
          field.isRequired = originalRequired;
          // print(
          //     'Restored field ${field.apiName} to editable = ${field.editable}, required = ${field.isRequired}');
        }
      }
    }

    // Trigger form validation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (formKey.currentState != null) {
          // Validate the form
          formKey.currentState!.validate();

          // Mark form fields for rebuild
          if (context is Element && context.mounted) {
            context.markNeedsBuild();

            // Also mark parent form for rebuild
            context.visitAncestorElements((element) {
              element.markNeedsBuild();
              return true;
            });
          }

          // Ensure controllers are synced with values
          for (var field in _allFormFields!) {
            if (field._controller != null && field.value != null) {
              if (field._controller!.text != field.value) {
                field._controller!.text = field.value!;
              }
            }
          }
        }

        // Force a UI update
        if (context.mounted) {
          (context as Element).markNeedsBuild();
          WidgetsBinding.instance.scheduleFrame();
        }
      } catch (e) {
        print('Error updating form validation: $e');
      }
    });

    // Print debug information
    // print('Disbursal status updated to: $disbursalStatus');
    // print(
    //     'Fields updated based on disbursal status (Status__c remains editable)');
  }

  // Method to handle Disbursal Status field changes
  static void updateDisbursalStatus(String? newStatus) {
    if (disbursalStatus == newStatus) return; // No change

    disbursalStatus = newStatus;

    if (_allFormFields == null) return;

    bool foundDisbursalStatusField = false;
    bool makeReadOnly = disbursalStatus == 'Not disbursed';
    bool isDisbursed = disbursalStatus == 'Disbursed';

    // Process fields after Disbursal Status field
    for (var field in _allFormFields!) {
      // Skip fields that cannot be modified based on original schema
      if (!_canModifyField(field)) {
        continue;
      }

      // Once we find the Disbursal Status field, mark it so we know to process subsequent fields
      if (field.apiName == 'Disbursal_Status__c') {
        foundDisbursalStatusField = true;
        continue; // Skip this field itself
      }

      // Special handling for If_others_then__c and If_not_disbursed__c fields
      if (field.apiName == 'If_others_then__c' ||
          field.apiName == 'If_not_disbursed__c') {
        // Disable these fields if 'Disbursed' is selected
        if (isDisbursed) {
          field.editable = false;
          field.isRequired = false; // Also make them not required
          field.value = ''; // Clear their values
        } else if (makeReadOnly) {
          // For "Not disbursed", keep these fields editable
          field.editable = true;
          field.isRequired = true; // Make them required
        } else {
          // For any other status (e.g. "Others"), keep these fields editable
          field.editable = true;
          field.isRequired = false;
        }
        continue; // Skip further processing for these special fields
      }

      // Special handling for Status__c field - always keep editable if originally editable
      if (field.apiName == 'Status__c') {
        // Skip making Status__c read-only, keep it editable regardless of disbursal status
        continue;
      }

      // Make all other fields after the Disbursal Status field read-only if "Not disbursed" is selected
      if (foundDisbursalStatusField) {
        Map<String, dynamic>? originalState =
            _originalFieldStates?[field.apiName];
        bool wasOriginallyEditable = originalState?['editable'] ?? false;
        bool wasOriginallyRequired = originalState?['isRequired'] ?? false;
        field.editable = makeReadOnly ? false : wasOriginallyEditable;
        field.isRequired = makeReadOnly ? false : wasOriginallyRequired;
      }
    }

    // Print debug information
    // print('Disbursal status updated to: $disbursalStatus');
    // print(
    //     'Fields updated based on disbursal status (Status__c remains editable)');
  }

  // Check if this is a Live_Disbursement form and initialize Disbursal Status if found
  static void _checkForDisbursalStatusField() {
    if (_allFormFields == null) return;

    FormModel? disbursalStatusField;
    FormModel? loanPassbookField;
    FormModel? loanPerpetualField;
    FormModel? noReasonField;
    FormModel? yesApplicantField;
    FormModel? notDisbursedField;
    FormModel? othersReasonField;
    // We'll track Live_Disbursement fields through individual variables

    // Find the Disbursal Status field and other relevant fields
    for (var field in _allFormFields!) {
      if (field.recordType == 'Live_Disbursement') {
        // Find all relevant fields
        if (field.apiName == 'Disbursal_Status__c') {
          disbursalStatusField = field;
        } else if (field.apiName == 'Loan_Passbook_issued_Response__c') {
          loanPassbookField = field;
        } else if (field.apiName ==
            'Whether_the_loan_applied_is_Perpetual__c') {
          loanPerpetualField = field;
        } else if (field.apiName == 'If_No_mention_the_reason__c') {
          noReasonField = field;
        } else if (field.apiName == 'If_Yes_applicant_should_know_other__c') {
          yesApplicantField = field;
        } else if (field.apiName == 'If_not_disbursed__c') {
          notDisbursedField = field;
        } else if (field.apiName == 'If_others_then__c') {
          othersReasonField = field;
        }
      }
    }

    // If we found the disbursal status field, initialize its status
    if (disbursalStatusField != null) {
      updateDisbursalStatus(disbursalStatusField.value);
    }

    // Handle Loan_Passbook_issued_Response__c dependency
    if (loanPassbookField != null && noReasonField != null) {
      // If Loan_Passbook_issued_Response__c is "Yes", make If_No_mention_the_reason__c non-editable
      if (loanPassbookField.value == 'Yes') {
        noReasonField.editable = false;
        noReasonField.value = ''; // Clear the value
        // print(
        //     'Initialized If_No_mention_the_reason__c: Editable = false based on Loan_Passbook_issued_Response__c = Yes');
      }
    }

    // Handle Whether_the_loan_applied_is_Perpetual__c dependency
    if (loanPerpetualField != null && yesApplicantField != null) {
      // If Whether_the_loan_applied_is_Perpetual__c is "No", make If_Yes_applicant_should_know_other__c non-editable
      if (loanPerpetualField.value == 'No') {
        yesApplicantField.editable = false;
        yesApplicantField.value = ''; // Clear the value
        // print(
        //     'Initialized If_Yes_applicant_should_know_other__c: Editable = false based on Whether_the_loan_applied_is_Perpetual__c = No');
      }
    }

    // Handle If_not_disbursed__c and If_others_then__c dependency
    if (notDisbursedField != null && othersReasonField != null) {
      // If If_not_disbursed__c is "others", make If_others_then__c editable and required
      bool isOthersSelected =
          notDisbursedField.value?.toLowerCase() == 'others';
      othersReasonField.editable = isOthersSelected;
      othersReasonField.isRequired = isOthersSelected;

      // If not "others", clear the value
      if (!isOthersSelected) {
        othersReasonField.value = '';
      }

      // print(
      //     'Initialized If_others_then__c: Editable = ${othersReasonField.editable}, Required = ${othersReasonField.isRequired} based on If_not_disbursed__c = ${notDisbursedField.value}');
    }
  }

  // Static method to mark fields as reference-related
  static void markReferenceRelatedFields(
      String referenceFieldLabel, List<String> fieldLabels) {
    if (_allFormFields == null) {
      return;
    }

    for (var field in _allFormFields!) {
      if (fieldLabels.contains(field.label)) {
        field.isReferenceRelatedField = true;
        field.relatedReferenceField = referenceFieldLabel;
        // Make the field read-only if it's related to a reference field
        field.editable = false;
      }
    }
  }

  // Method to update other form fields based on API response
  static void updateFormFieldsFromApiResponse(
      Map<String, dynamic> apiData, BuildContext context,
      {String? referenceFieldLabel}) {
    if (_allFormFields == null) {
      return;
    }

    // This empty loop was removed as it's not needed

    // Special debug for Territory field
    for (var field in _allFormFields!) {
      if (field.label.toLowerCase() == "territory") {}
    }

    apiData.forEach((key, value) {});

    // Flag to track if we need to update the UI
    bool updatedAnyField = false;

    // For each key in API response, try to find matching form field by label
    apiData.forEach((apiKey, apiValue) {
      // Skip null values
      if (apiValue == null) {
        return;
      }

      bool fieldFound = false;
      FormModel? matchedEditableField;
      FormModel? matchedReadOnlyField;

      // Special handling for Territory field
      if (apiKey.toLowerCase() == "territory") {}

      // First pass: Find all matching fields and categorize as editable or read-only
      for (var field in _allFormFields!) {
        // Try both exact match and case-insensitive match
        if (field.label == apiKey ||
            field.label.toLowerCase() == apiKey.toLowerCase()) {
          // Keep track of whether we found editable or read-only fields
          if (field.editable) {
            matchedEditableField = field;
            if (apiKey.toLowerCase() == "territory") {}
          } else {
            matchedReadOnlyField = field;
            if (apiKey.toLowerCase() == "territory") {}
          }
          fieldFound = true;
        }
      }

      // Second pass: Update the field, prioritizing editable fields
      if (matchedEditableField != null) {
        // Prefer updating editable fields
        String oldValue = matchedEditableField.value ?? "null";
        String newValue = apiValue.toString();

        // Only update if value actually changed
        if (oldValue != newValue) {
          matchedEditableField.value = newValue;
          updatedAnyField = true;
        } else {}
      } else if (matchedReadOnlyField != null) {
        // Fall back to read-only fields if no editable field exists
        String oldValue = matchedReadOnlyField.value ?? "null";
        String newValue = apiValue.toString();

        // Only update if value actually changed
        if (oldValue != newValue) {
          matchedReadOnlyField.value = newValue;
          updatedAnyField = true;
        } else {}
      } else if (!fieldFound) {}
    });

    // Check Territory fields after update
    for (var field in _allFormFields!) {
      if (field.label.toLowerCase() == "territory") {}
    }

    // If this update is from a reference API call, track the fields being updated
    // This list was previously unused and has been removed

    // Only trigger UI update if we actually changed any field
    if (updatedAnyField) {
      // Force UI refresh
      try {
        if (context.mounted) {
          // Schedule a frame to rebuild the UI
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              // This is a more aggressive approach that should work in all cases
              Future.microtask(() {
                for (var field in _allFormFields!) {
                  // Force controller update for text fields
                  if (field._controller != null && field.value != null) {
                    // Update text field controllers
                    if (field._controller!.text != field.value) {
                      field._controller!.text = field.value!;
                    }
                  }
                }
              });

              // Schedule a UI rebuild
              WidgetsBinding.instance.scheduleFrame();
            } catch (e) {}
          });
        }
      } catch (e) {}
    } else {}

    // Refresh the form UI to show updated values
    try {
      if (context.mounted) {
        // Use post frame callback to mark all ancestors for rebuild
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            // Force rebuild using a more robust approach
            Element? element = context as Element?;
            if (element != null && element.mounted) {
              element.markNeedsBuild();

              // Also mark parents for rebuild
              element.visitAncestorElements((ancestor) {
                ancestor.markNeedsBuild();
                return true; // Continue visiting
              });
            }
          } catch (e) {}
        });

        // Force a visual refresh
        WidgetsBinding.instance.scheduleFrame();
      } else {}
    } catch (e) {}
  }

  // Add this method to show loading dialog
  static void showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: Lottie.asset(
                    'assets/animations/Loading1.json',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Fetching details...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Update the handleReferenceApiResponse method to make fields non-editable with visual styling
  static void handleReferenceApiResponse(
      dynamic result, BuildContext context, String referenceFieldLabel) {
    try {
      bool success = false;
      String message = 'No data found';

      if (result['success'] == true && result['data'] != null) {
        final responseData = result['data'];
        if (responseData is List && responseData.isNotEmpty) {
          final referenceData = responseData[0];
          if (referenceData is Map<String, dynamic>) {
            final processedData = Map<String, dynamic>();

            if (_allFormFields != null) {
              referenceData.forEach((apiKey, apiValue) {
                bool fieldFound = false;
                for (var field in _allFormFields!) {
                  if (field.apiName == apiKey ||
                      field.label.toLowerCase() == apiKey.toLowerCase()) {
                    processedData[field.label] = apiValue;
                    fieldFound = true;
                  }
                }

                if (!fieldFound) {
                  processedData[apiKey] = apiValue;
                }
              });

              // List to track which fields were updated by the reference API
              List<String> updatedFieldLabels = [];

              // Update form fields with values from the processed API response
              updateFormFieldsFromApiResponse(processedData, context);

              // Make all updated fields non-editable with grey background
              if (_allFormFields != null) {
                _allFormFields!.forEach((field) {
                  // Check if this field was updated by the reference API
                  if (processedData.containsKey(field.label)) {
                    // Field was updated by reference API, make it non-editable
                    field.editable = false;

                    // Add to tracking list
                    updatedFieldLabels.add(field.label);

                    // Don't set isReferenceRelatedField or relatedReferenceField
                    // so no extra label will be shown
                  }
                });
              }

              // Log which fields were made non-editable
              // print(
              //     'Fields made non-editable after fetch code API: ${updatedFieldLabels.join(', ')}');

              // Set success flag to show appropriate message
              success = true;
              message = 'Details fetched successfully!';
            } else {
              // Fall back to original data if form fields are not set
              message = 'Form fields not initialized properly';
            }
          } else {
            message = 'Data received in unexpected format';
          }
        } else {
          message = 'No data found for this code';
        }
      } else {
        message = result['message'] ?? 'Failed to fetch details';
      }

      // Close any open dialogs (including loading dialog)
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // Show appropriate snackbar message based on success/failure
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog on error
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();

        // Show error snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } finally {
      // Reset loading state regardless of success or failure
      isReferenceApiLoading = false;

      // Force UI update to hide loading animation
      if (context is Element && context.mounted) {
        context.markNeedsBuild();
      }
    }
  }

  factory FormModel.fromJson(Map<String, dynamic> json) {
    // Handle picklistValues which might be stored in different formats
    List<String>? picklistOptions;
    if (json['picklistValues'] != null) {
      if (json['picklistValues'] is List) {
        picklistOptions = List<String>.from(
            json['picklistValues'].map((item) => item.toString()));
      } else if (json['picklistValues'] is String) {
        // Handle case where options might be stored as comma-separated string
        picklistOptions = json['picklistValues'].toString().split(',');
      }
    }

    return FormModel(
      type: json['type'] ?? '',
      label: json['label'] ?? '',
      editable: json['editable'] ?? true,
      apiName: json['apiName'] ?? '',
      pageType: json['pageType'] ?? '',
      value: json['value']?.toString(),
      recordType: json['recordType'],
      isRequired: json['isRequired'] ?? true,
      //isRequired: true,
      picklistValues: picklistOptions,
    );
  }

  // Update getWidget to handle reference-related fields differently
  Widget getWidget(GlobalKey<FormState> formKey, BuildContext context) {
    final isReadOnly = !editable || isReferenceRelatedField;

    // For reference-related fields, show where they came from
    if (isReferenceRelatedField && relatedReferenceField != null) {
      // Create a modified version of each field type that shows it's reference-related
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(from ${relatedReferenceField!})',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // The rest of the field rendering stays the same, but with isReadOnly = true
          // ...existing field rendering code based on type...

          // Example for Text type (the other types would follow the same pattern)
          if (type == 'Text')
            TextFormField(
              controller: _controller,
              readOnly: true, // Always read-only for reference-related fields
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                fillColor: Colors
                    .grey[100], // Light grey background to indicate read-only
                filled: true,
              ),
              onChanged: (val) => value = val,
            )
          else
            // Continue with the existing switch/case for other field types
            // The original widget, but with isReadOnly = true
            _getOriginalWidget(formKey, context, isReadOnly: true),
        ],
      );
    }

    // For regular fields, use the existing rendering
    return _getOriginalWidget(formKey, context, isReadOnly: isReadOnly);
  }

  // Move the original widget rendering to a private method
  Widget _getOriginalWidget(GlobalKey<FormState> formKey, BuildContext context,
      {required bool isReadOnly}) {
    // Define a consistent decoration for non-editable fields
    InputDecoration getFieldDecoration() {
      return InputDecoration(
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        // Apply darker grey background color to non-editable fields
        fillColor: isReadOnly ? Colors.grey[300] : Colors.white,
        filled: isReadOnly,
        // Use a slightly darker border color for non-editable fields
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: isReadOnly ? Colors.grey[500]! : Colors.grey[600]!,
          ),
        ),
      );
    }

    // Define consistent text style for all fields
    TextStyle getTextStyle() {
      return TextStyle(
        color: isReadOnly ? Colors.black87 : Colors.black,
        fontWeight: isReadOnly ? FontWeight.w500 : FontWeight.normal,
      );
    }

    switch (type) {
      // Add new case for image capture
      case 'Image':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            getLabelWidget(), // Use getLabelWidget instead of Text
            const SizedBox(height: 8),

            // Image preview or placeholder
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _imageFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(
                        _imageFile!,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Center(
                      child: Icon(
                        Icons.add_a_photo,
                        size: 50,
                        color: Colors.grey[400],
                      ),
                    ),
            ),

            const SizedBox(height: 8),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Camera button
                ElevatedButton.icon(
                  onPressed: isReadOnly
                      ? null
                      : () async {
                          final success = await captureImage(context);
                          if (success && context is StatefulElement) {
                            context.markNeedsBuild();
                          }
                        },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F2B5B),
                  ),
                ),

                // Gallery button
                ElevatedButton.icon(
                  onPressed: isReadOnly
                      ? null
                      : () async {
                          final success = await pickImageFromGallery(context);
                          if (success && context is StatefulElement) {
                            context.markNeedsBuild();
                          }
                        },
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F2B5B),
                  ),
                ),

                // Clear button (only show when image exists)
                if (_imageFile != null)
                  ElevatedButton.icon(
                    onPressed: isReadOnly
                        ? null
                        : () {
                            clearImage();
                            if (context is StatefulElement) {
                              context.markNeedsBuild();
                            }
                          },
                    icon: const Icon(Icons.delete),
                    label: const Text('Clear'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
              ],
            ),

            // Validation message
            if (isRequired && _imageBytes == null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Image is required',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );

      // case 'ReadOnly':
      //   // Use ValueListenable to ensure the UI updates when the value changes
      //   return Column(
      //     crossAxisAlignment: CrossAxisAlignment.start,
      //     children: [
      //       getLabelWidget(), // Use getLabelWidget instead of Text
      //       const SizedBox(height: 4),
      //       StatefulBuilder(
      //         builder: (BuildContext context, StateSetter setState) {
      //           // Create a unique key for this container to force rebuild
      //           return Container(
      //             key: ValueKey(
      //                 'readonly_${label}_${value}_${DateTime.now().millisecondsSinceEpoch}'),
      //             width: double.infinity,
      //             padding:
      //                 const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      //             decoration: BoxDecoration(
      //               color: Colors.grey[
      //                   300], // Use same grey as other non-editable fields
      //               borderRadius: BorderRadius.circular(4),
      //               border: Border.all(
      //                   color: Colors.grey[500]!), // Match the border color
      //             ),
      //             child: Text(
      //               value ?? '',
      //               style: getTextStyle(), // Use the same text style
      //             ),
      //           );
      //         },
      //       ),
      //     ],
      //   );
      case 'Text':
        // Create or update controller when needed
        _controller ??= TextEditingController(text: value);
        if (_controller!.text != value && value != null) {
          _controller!.text = value!;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            getLabelWidget(), // Use getLabelWidget instead of Text
            const SizedBox(height: 8),
            TextFormField(
              controller: _controller,
              inputFormatters: [
                LengthLimitingTextInputFormatter(50),
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 ]')),
                FilteringTextInputFormatter.deny(RegExp(r'[-+!@#$%^&*()]'))
              ],
              readOnly: isReadOnly,
              decoration: getFieldDecoration(),
              maxLines: value != null && value!.length > 40 ? null : 1,
              validator: (val) {
                // Print validation state for debugging
                //print('Validating $apiName: Required=$isRequired, Value=$val');

                if (isRequired && editable && (val == null || val.isEmpty)) {
                  return '$label is required';
                }
                return null;
              },
              onChanged: (val) => value = val,
              // Use dark text for non-editable fields
              style: getTextStyle(),
            ),
          ],
        );

      case 'reference':
        // Create or update controller when needed
        _controller ??= TextEditingController(text: value);
        if (_controller!.text != value && value != null) {
          _controller!.text = value!;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            getLabelWidget(), // Use getLabelWidget instead of Text
            const SizedBox(height: 8), // Space between label and field
            Stack(
              children: [
                TextFormField(
                  controller: _controller,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(20),
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 ]')),
                    FilteringTextInputFormatter.deny(RegExp(r'[-+!@#$%^&*()]'))
                  ],
                  readOnly: isReadOnly || FormModel.isReferenceApiLoading,
                  decoration: getFieldDecoration().copyWith(
                    suffixIcon: !FormModel.isReferenceApiLoading
                        ? IconButton(
                            icon: Icon(
                              Icons.search,
                              color:
                                  isReadOnly ? Colors.grey[500] : Colors.blue,
                            ),
                            onPressed: isReadOnly
                                ? null
                                : () async {
                                    // Search icon click handler
                                    if (value != null && value!.isNotEmpty) {
                                      try {
                                        // Show loading dialog
                                        FormModel.showLoadingDialog(context);

                                        // Set loading state to true
                                        FormModel.isReferenceApiLoading = true;

                                        final apiCall = ApiCall();
                                        final result = await apiCall.callApi(
                                          endpoint: 'reference',
                                          objectType: apiName,
                                          code: value,
                                        );

                                        // Pass the current field's label as the reference field label
                                        FormModel.handleReferenceApiResponse(
                                            result, context, label);
                                      } catch (e) {
                                        // Close loading dialog on error
                                        Navigator.of(context,
                                                rootNavigator: true)
                                            .pop();

                                        // Reset loading state on error
                                        FormModel.isReferenceApiLoading = false;

                                        // Show error message
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Error: ${e.toString()}'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    } else {
                                      // Show a message if field is empty
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Please enter a value first'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                          )
                        : null,
                    hintText: 'Enter code and press Enter/Done',
                  ),
                  style: getTextStyle(),
                  validator: (val) {
                    if (isRequired &&
                        editable &&
                        (val == null || val.isEmpty)) {
                      return '$label is required';
                    }
                    return null;
                  },
                  onChanged: (val) => value = val,
                  // Call API when editing is complete (user presses Enter/Done)
                  onEditingComplete: () async {
                    // Check if value exists and is not empty
                    if (value != null && value!.isNotEmpty) {
                      try {
                        // Show loading dialog
                        FormModel.showLoadingDialog(context);

                        // Set loading state to true
                        FormModel.isReferenceApiLoading = true;

                        final apiCall = ApiCall();
                        final result = await apiCall.callApi(
                          endpoint: 'reference',
                          objectType: apiName,
                          code: value,
                        );

                        // Pass the current field's label as the reference field label
                        FormModel.handleReferenceApiResponse(
                            result, context, label);
                      } catch (e) {
                        // Close loading dialog on error
                        Navigator.of(context, rootNavigator: true).pop();

                        // Reset loading state on error
                        FormModel.isReferenceApiLoading = false;

                        // Show error message
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  // Also update onFieldSubmitted similarly:
                  onFieldSubmitted: (val) async {
                    if (val.isNotEmpty) {
                      try {
                        // Show loading dialog
                        FormModel.showLoadingDialog(context);

                        // Set loading state to true
                        FormModel.isReferenceApiLoading = true;

                        final apiCall = ApiCall();
                        final result = await apiCall.callApi(
                          endpoint: 'reference',
                          objectType: apiName,
                          code: val,
                        );

                        // Pass the current field's label as the reference field label
                        FormModel.handleReferenceApiResponse(
                            result, context, label);
                      } catch (e) {
                        // Close loading dialog on error
                        Navigator.of(context, rootNavigator: true).pop();

                        // Reset loading state on error
                        FormModel.isReferenceApiLoading = false;

                        // Show error message
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
                // Loading animation overlay
                if (FormModel.isReferenceApiLoading)
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Lottie.asset(
                        'assets/animations/Loading1.json',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );

      case 'Picklist':
        //final List<String> options = ['Select an option', ...?picklistValues];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            getLabelWidget(), // Use getLabelWidget instead of Text
            const SizedBox(height: 8), // Space between label and field

            // Check if options are just Yes/No to render radio buttons
            // if (picklistValues != null &&
            //     picklistValues?.length == 2 &&
            //     picklistValues!.contains('Yes') &&
            //     picklistValues!.contains('No'))
            //   // Radio button implementation for Yes/No
            //   Row(
            //     children: [
            //       Radio<String>(
            //         value: 'Yes',
            //         groupValue: value,
            //         onChanged: isReadOnly
            //             ? null
            //             : (val) {
            //                 if (val != null) {
            //                   value = val;
            //                   // Use setState in a StatefulWidget instead
            //                   if (context is StatefulElement) {
            //                     (context as StatefulElement).markNeedsBuild();
            //                   } else {
            //                     // Force rebuild in a safer way
            //                     Future.microtask(() =>
            //                         formKey.currentState?.setState(() {}));
            //                   }
            //                 }
            //               },
            //       ),
            //       const Text('Yes'),
            //       const SizedBox(width: 20), // Space between options
            //       Radio<String>(
            //         value: 'No',
            //         groupValue: value,
            //         onChanged: isReadOnly
            //             ? null
            //             : (val) {
            //                 if (val != null) {
            //                   value = val;
            //                   // Use setState in a StatefulWidget instead
            //                   if (context is StatefulElement) {
            //                     (context as StatefulElement).markNeedsBuild();
            //                   } else {
            //                     // Force rebuild in a safer way
            //                     Future.microtask(() =>
            //                         formKey.currentState?.setState(() {}));
            //                   }
            //                 }
            //               },
            //       ),
            //       const Text('No'),
            //     ],
            //   )
            // else
            // Default dropdown implementation for all other cases
            DropdownButtonFormField<String>(
                isExpanded: true,
                value: value?.isNotEmpty == true ? value : null,
                decoration: getFieldDecoration(),
                style: getTextStyle(),
                items: [
                  DropdownMenuItem<String>(
                    value: null,
                    child: Text('Select an option',
                        style: isReadOnly
                            ? getTextStyle()
                            : const TextStyle(color: Colors.grey)),
                  ),
                  ...(picklistValues ?? [])
                      .map((opt) => DropdownMenuItem(
                          value: opt, child: Text(opt, style: getTextStyle())))
                      .toList(),
                ],
                validator: (val) {
                  // Special validation for Gold_Loan - always require a value if editable
                  if ((recordType == 'Gold_Loan' && editable && val == null) ||
                      (isRequired && editable && val == null)) {
                    return '$label is required';
                  }
                  return null;
                },
                onChanged: isReadOnly
                    ? null
                    : (val) {
                        if (val != null) {
                          // We don't need to store the previous value anymore
                          // String? previousValue = value;

                          // Update value
                          value = val;

                          // Special handling for Live_Disbursement fields
                          if (recordType == 'Live_Disbursement') {
                            if (apiName == 'Disbursal_Status__c') {
                              // Call the correct method with context and formKey
                              FormModel.updateLiveDisbursalStatus(
                                  val, context, formKey);
                            } else if (apiName ==
                                'Loan_Passbook_issued_Response__c') {
                              // Find and update If_No_mention_the_reason__c field
                              for (var field in _allFormFields!) {
                                if (field.apiName ==
                                        'If_No_mention_the_reason__c' &&
                                    field.recordType == 'Live_Disbursement') {
                                  // Make editable only if not "Yes"
                                  bool shouldBeEditable = val != 'Yes';
                                  field.editable = shouldBeEditable;

                                  // If making non-editable, clear the value
                                  if (!shouldBeEditable) {
                                    field.value = '';
                                  }
                                  // print(
                                  //     'Updated If_No_mention_the_reason__c: Editable = $shouldBeEditable');
                                  break;
                                }
                              }
                            } else if (apiName ==
                                'Whether_the_loan_applied_is_Perpetual__c') {
                              // Find and update If_Yes_applicant_should_know_other__c field
                              for (var field in _allFormFields!) {
                                if (field.apiName ==
                                        'If_Yes_applicant_should_know_other__c' &&
                                    field.recordType == 'Live_Disbursement') {
                                  // Make editable only if not "No"
                                  bool shouldBeEditable = val != 'No';
                                  field.editable = shouldBeEditable;

                                  // If making non-editable, clear the value
                                  if (!shouldBeEditable) {
                                    field.value = '';
                                  }
                                  // print(
                                  //     'Updated If_Yes_applicant_should_know_other__c: Editable = $shouldBeEditable');
                                  break;
                                }
                              }
                            } else if (apiName == 'If_not_disbursed__c') {
                              FormModel.updateNotDisbursedReason(
                                  val, context, formKey);
                            }
                          }

                          // Special handling for BPM_Appraisal fields
                          if (recordType == 'BPM_Appraisal') {
                            if (apiName == 'Did_BPM_visited_all_residence_of_borrowe__c' ||
                                apiName ==
                                    'Did_BPM_verified_all_documents_of_borrow__c' ||
                                apiName ==
                                    'Did_BPM_verified_Borrowers_Bank_Passbook__c') {
                              FormModel.updateBPMAppraisalRequirements(
                                  val, apiName, context, formKey);
                            }
                          }

                          // Special handling for Collection Audit Status field
                          if (recordType == 'Collection_Audit') {
                            if (apiName == 'Status__c') {
                              FormModel.updateCollectionAuditStatus(
                                  val, context, formKey);
                            }
                          }

                          // Special handling for PDAV fields
                          if (recordType == 'PDAV') {
                            if (apiName ==
                                'Is_the_Asset_seen_at_the_time_of_visit__c') {
                              FormModel.updateAssetVisibilityRequirements(
                                  val, context, formKey);
                            } else if (apiName ==
                                'Is_the_customer_s_address_traceable__c') {
                              FormModel.updateCustomerAddressTraceability(
                                  val, context, formKey);
                            } else if (apiName == 'Assigned_To__c') {
                              FormModel.updateAssignmentStatus(
                                  val, context, formKey);
                            } else if (apiName ==
                                'Insurance_Certificate_received__c') {
                              FormModel.updateInsuranceCertificateRequirements(
                                  val, context, formKey);
                            } else if (apiName ==
                                'Confirm_Asset_Make_Model__c') {
                              FormModel.updateAssetMakeModelMatch(
                                  val, context, formKey);
                            } else if (apiName == 'RC_received__c') {
                              FormModel.updateRCReceivedStatus(
                                  val, context, formKey);
                              if (context is StatefulElement) {
                                (context).markNeedsBuild();
                              }
                            } else if (apiName == 'Local_or_OGL_Pick__c') {
                              FormModel.updateOGLStatus(val, context, formKey);
                            }
                            if (context is StatefulElement) {
                              (context).markNeedsBuild();
                            }

                            // Special handling for PDAV loan relationship field
                            if (apiName ==
                                    'Is_the_loan_taken_for_self_Yes_No__c' &&
                                recordType == 'PDAV') {
                              // Debug print to confirm we're entering this condition
                              // print('PDAV loan relationship changed to: $val');
                              FormModel.updateCollectionAuditLoanRelationship(
                                  val, context, formKey);
                            }

                            // Use setState in a StatefulWidget instead
                            if (context is StatefulElement) {
                              context.markNeedsBuild();
                            } else {
                              // Force rebuild in a safer way
                              Future.microtask(() {
                                if (formKey.currentContext != null &&
                                    formKey.currentContext is Element) {
                                  (formKey.currentContext as Element)
                                      .markNeedsBuild();
                                }
                              });
                            }
                          }
                        }
                      }),
          ],
        );
      case 'Phone':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            getLabelWidget(), // Use getLabelWidget instead of Text
            const SizedBox(
                height: 8), // Add some spacing between label and field
            TextFormField(
              initialValue: value,
              readOnly: isReadOnly,
              decoration: getFieldDecoration(),
              keyboardType: TextInputType.phone,
              validator: (val) {
                if (isRequired && editable && (val == null || val.isEmpty)) {
                  return '$label is required';
                }
                return null;
              },
              onChanged: (val) => value = val,
              // Use dark text for non-editable fields
              style: getTextStyle(),
            ),
          ],
        );

      case 'Date':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            getLabelWidget(),
            const SizedBox(height: 8),
            TextFormField(
              controller: TextEditingController(text: value),
              readOnly:
                  true, // Make it read-only since we'll use the date picker
              decoration: getFieldDecoration().copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.calendar_today,
                    color: isReadOnly ? Colors.grey[500] : Colors.blue,
                  ),
                  onPressed: isReadOnly
                      ? null
                      : () async {
                          DateTime? initialDate;
                          if (value != null && value!.isNotEmpty) {
                            try {
                              initialDate =
                                  DateFormat('yyyy-MM-dd').parse(value!);
                              // If initial date is in future, set to today
                              if (initialDate.isAfter(DateTime.now())) {
                                initialDate = DateTime.now();
                              }
                            } catch (e) {
                              // If parsing fails, use today's date
                              initialDate = DateTime.now();
                            }
                          } else {
                            initialDate = DateTime.now();
                          }

                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: initialDate,
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(), // Prevent future dates
                            selectableDayPredicate: (DateTime day) {
                              // Return false for future dates to make them unselectable
                              return !day.isAfter(DateTime.now());
                            },
                          );

                          if (picked != null) {
                            final String formattedDate =
                                DateFormat('yyyy-MM-dd').format(picked);
                            // Update both the controller and the value
                            value = formattedDate;

                            // Check if this is a From_Date__c or To_Date__c field in Cross_Audit form
                            if ((apiName == 'From_Date__c' ||
                                    apiName == 'To_Date__c') &&
                                recordType == 'Cross_Audit') {
                              // Calculate date difference for Cross_Audit
                              updateDateDifferenceForCrossAudit(
                                  context, formKey);
                            }

                            // Force rebuild
                            if (context is StatefulElement) {
                              (context).markNeedsBuild();
                            } else {
                              // Safer method
                              Future.microtask(() =>
                                  (formKey.currentContext as Element?)
                                      ?.markNeedsBuild());
                            }
                          }
                        },
                ),
              ),
              style: getTextStyle(),
              validator: (val) {
                if (isRequired && editable && (val == null || val.isEmpty)) {
                  return '$label is required';
                }
                return null;
              },
            ),
          ],
        );

      case 'Text Area':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            getLabelWidget(), // Use getLabelWidget instead of Text
            const SizedBox(height: 8), // Space between label and textarea
            TextFormField(
              initialValue: value,
              readOnly: isReadOnly,
              maxLines: 4, // Multiple lines for textarea
              decoration: getFieldDecoration(),
              style: getTextStyle(),
              validator: (val) {
                if (isRequired && editable && (val == null || val.isEmpty)) {
                  return '$label is required';
                }
                return null;
              },
              onChanged: (val) => value = val,
            ),
          ],
        );

      case 'Date/Time':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            getLabelWidget(), // Use getLabelWidget instead of Text
            const SizedBox(height: 8), // Space between label and field
            TextFormField(
              controller: TextEditingController(text: value),
              readOnly:
                  true, // Make it read-only since we'll use the date picker
              decoration: getFieldDecoration().copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    Icons.calendar_today,
                    color: isReadOnly ? Colors.grey[500] : Colors.blue,
                  ),
                  onPressed: isReadOnly
                      ? null
                      : () async {
                          DateTime? initialDate;
                          if (value != null && value!.isNotEmpty) {
                            try {
                              initialDate =
                                  DateFormat('yyyy-MM-dd').parse(value!);
                            } catch (e) {
                              // If parsing fails, use today's date
                              initialDate = DateTime.now();
                            }
                          } else {
                            initialDate = DateTime.now();
                          }

                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: initialDate,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            final String formattedDate =
                                DateFormat('yyyy-MM-dd').format(picked);
                            // Update both the controller and the value
                            value = formattedDate;
                            // Force rebuild
                            if (context is StatefulElement) {
                              (context).markNeedsBuild();
                            } else {
                              // Safer method
                              Future.microtask(() =>
                                  (formKey.currentContext as Element?)
                                      ?.markNeedsBuild());
                            }
                          }
                        },
                ),
              ),
              style: getTextStyle(),
              validator: (val) {
                if (isRequired && editable && (val == null || val.isEmpty)) {
                  return '$label is required';
                }
                return null;
              },
            ),
          ],
        );

      case 'Number':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            getLabelWidget(), // Use getLabelWidget instead of Text
            const SizedBox(height: 8), // Space between label and field
            TextFormField(
              inputFormatters: [
                LengthLimitingTextInputFormatter(10),
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                FilteringTextInputFormatter.deny(
                    RegExp(r'[-+!@#$%^&*()a-zA-Z]'))
              ],
              initialValue: value,
              readOnly: isReadOnly,
              decoration: getFieldDecoration(),
              keyboardType: TextInputType.number,
              // Use dark text for non-editable fields
              style: getTextStyle(),
              validator: (val) {
                if (isRequired && editable && (val == null || val.isEmpty)) {
                  return '$label is required';
                }
                if (val != null &&
                    val.isNotEmpty &&
                    double.tryParse(val) == null) {
                  return 'Please enter a valid number';
                }
                return null;
              },
              onChanged: (val) => value = val,
            ),
          ],
        );

      // For all other field types, update with the same pattern
      default:
        //return Null;
        //return SizedBox();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              getLabelWidget(), // Use getLabelWidget instead of Text
              const SizedBox(height: 8),
              TextFormField(
                initialValue: value,
                readOnly: true,
                enabled: false,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  hintText: 'No value available',
                  fillColor: Colors.grey[300], // Match the grey color
                  filled: true,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.grey[500]!, // Match the border color
                    ),
                  ),
                ),
                style: getTextStyle(), // Use the same text style
              ),
              // if (type != 'Text')
              //   Padding(
              //     padding: const EdgeInsets.only(top: 4),
              //     child: Text(
              //       'Field type: $type',
              //       style: TextStyle(
              //         fontSize: 12,
              //         color: Colors.grey.shade600,
              //         fontStyle: FontStyle.italic,
              //       ),
              //     ),
              //   ),
            ],
          ),
        );
    }
  }

  static void _updatePDAVFieldsVisibility() {
    if (_allFormFields == null) {
      return;
    }

    // Check if this is a PDAV recordType form
    bool isPDAVForm = false;
    FormModel? assetSeenField;
    FormModel? customerAddressField;
    FormModel? insuranceCertificateField;
    FormModel? assignedToField;
    FormModel? rcReceivedField;
    FormModel? localOGLField;

    // Check if this is a BPM_Appraisal form
    bool isBPMAppraisalForm = false;
    Map<String, FormModel> bpmTriggerFields = {};
    Map<String, String> bpmDependentFieldMap = {
      'Did_BPM_visited_all_residence_of_borrowe__c': 'If_no_Mention_Lan__c',
      'Did_BPM_verified_all_documents_of_borrow__c': 'If_no_Mention_Lan1__c',
      'Did_BPM_verified_Borrowers_Bank_Passbook__c': 'If_no_Mention_Lan2__c',
    };

    // Scan all fields to determine form type and collect PDAV trigger fields
    for (var field in _allFormFields!) {
      if (field.recordType == 'PDAV') {
        isPDAVForm = true;

        // Collect PDAV trigger fields
        if (field.apiName == 'Is_the_Asset_seen_at_the_time_of_visit__c') {
          assetSeenField = field;
        } else if (field.apiName == 'Is_the_customer_s_address_traceable__c') {
          customerAddressField = field;
        } else if (field.apiName == 'Insurance_Certificate_received__c') {
          insuranceCertificateField = field;
        } else if (field.apiName == 'Assigned_To__c') {
          assignedToField = field;
        } else if (field.apiName == 'RC_received__c') {
          rcReceivedField = field;
        } else if (field.apiName == 'Local_or_OGL_Pick__c') {
          localOGLField = field;
        }
      } else if (field.recordType == 'BPM_Appraisal') {
        isBPMAppraisalForm = true;

        // Collect BPM trigger fields
        if (bpmDependentFieldMap.keys.contains(field.apiName)) {
          bpmTriggerFields[field.apiName] = field;
        }
      }
    }

    // Handle PDAV form initialization
    if (isPDAVForm) {
      // 1. Handle customer address field - If No is selected, enable the dependent field
      if (customerAddressField != null) {
        final isAddressTraceable = customerAddressField.value;
        for (var field in _allFormFields!) {
          if (field.recordType == 'PDAV' &&
              field.apiName == 'If_No_Need_to_co_ordinate_escalated_to__c') {
            // Enable only if address is not traceable (No)
            field.editable = (isAddressTraceable == 'No');
            field.isRequired = (isAddressTraceable == 'No');

            if (!field.editable) {
              field.value = ''; // Clear value when disabled
            }
            // print(
            //     'Updated If_No_Need_to_co_ordinate_escalated_to__c: Editable = ${field.editable}');
          }
        }
      }

      // 2. Handle asset seen field
      if (assetSeenField != null) {
        final assetSeen = assetSeenField.value;

        // Fields to be mandatory and editable if asset is seen
        List<String> enabledIfSeen = [
          'Actual_Asset_Make_Model__c',
          'Does_asset_make_model_match_with_system__c',
          'Does_Asset_Registration_number_match__c',
          'Engine_number_as_per_vehicle_seen__c',
          'Chassis_number_as_per_vehicle_seen__c',
          'Do_the_details_in_INVOICE_matches__c',
          'RC_received_If_yes_please_share_RC_no__c',
          'If_No_mention_the_reason_PDAV__c',
          'Insurance_Certificate_received__c'
        ];

        // Fields to be mandatory and editable if asset is not seen
        List<String> enabledIfNotSeen = [
          'If_asset_not_seen_at_the_time_of_village__c',
          'If_asset_not_seen_at_the_time_of_visit__c',
          'Asset_available_with_whom__c',
          'If_third_party_take_details__c'
        ];

        // Update field requirements based on asset visibility
        for (var field in _allFormFields!) {
          // Skip if not a PDAV field
          if (field.recordType != 'PDAV') continue;

          // Special handling for the two fields that should always be enabled
          // if (field.apiName == 'If_No_mention_the_reason_PDAV__c' ||
          //     field.apiName == 'Insurance_Certificate_received__c') {
          //   // Keep these fields always enabled but mark as required only when asset is seen
          //   field.isRequired = (assetSeen == 'Yes');
          //   field.editable = true; // Always enabled
          //   continue; // Skip further processing for these fields
          // }

          // For fields that should be enabled if asset is seen
          if (enabledIfSeen.contains(field.apiName)) {
            field.isRequired = (assetSeen == 'Yes');
            field.editable = (assetSeen == 'Yes');

            if (!field.editable) {
              field.value = ''; // Clear value when disabled
            }
          }

          // For fields that should be enabled if asset is NOT seen
          if (enabledIfNotSeen.contains(field.apiName)) {
            field.isRequired = (assetSeen == 'No');
            field.editable = (assetSeen == 'No');

            if (!field.editable) {
              field.value = ''; // Clear value when disabled
            }
          }
        }
      }

      // 3. Handle RC_received__c field
      if (rcReceivedField != null) {
        final rcReceived = rcReceivedField.value;
        for (var field in _allFormFields!) {
          if (field.recordType == 'PDAV' &&
              field.apiName == 'If_yes_please_share_RC_number__c') {
            // Enable only if RC is received (Yes)
            field.editable = (rcReceived == 'Yes');
            field.isRequired = (rcReceived == 'Yes');

            if (!field.editable) {
              field.value = ''; // Clear value when disabled
            }
            // print(
            //     'Updated RC_received_If_yes_please_share_RC_no__c: Editable = ${field.editable}');
          }
        }
      }

      // Handle OGL field
      if (localOGLField != null) {
        final isOGL = localOGLField.value;
        for (var field in _allFormFields!) {
          if (field.recordType == 'PDAV' &&
              field.apiName == 'If_OGL_mention_Kms__c') {
            // Enable only if OGL is selected
            field.editable = (isOGL == 'OGL');
            field.isRequired = (isOGL == 'OGL');

            if (!field.editable) {
              field.value = ''; // Clear value when disabled
            }
            // print('Updated OGL_Number__c: Editable = ${field.editable}');
          }
        }
      }

      //   // Fields to enable if insurance certificate is NOT received
      //   List<String> enabledIfNoInsurance = [
      //     'If_No__c',
      //     'If_asset_not_seen_at_the_time_of_village__c',
      //     'If_asset_not_seen_at_the_time_of_visit__c',
      //     'Asset_available_with_whom__c',
      //     'If_third_party_take_details__c',
      //     'Confirm_Asset_Make_Model__c',
      //     'If_No_Match_mention_the_mismatched__c',
      //     'RC_received_If_yes_please_share_RC_no_2__c',
      //     'If_No_mention_the_reason__c'
      //   ];

      //   // Update field requirements based on insurance certificate status
      //   for (var field in _allFormFields!) {
      //     // Skip if not a PDAV field
      //     if (field.recordType != 'PDAV') continue;

      //     // Enable specified fields only if insurance certificate is not received
      //     if (enabledIfNoInsurance.contains(field.apiName)) {
      //       field.isRequired = (insuranceReceived == 'No');
      //       field.editable = (insuranceReceived == 'No');

      //       if (!field.editable) {
      //         field.value = ''; // Clear value when disabled
      //       }

      //       print('Updated ${field.apiName}: Editable = ${field.editable}');
      //     }
      //   }
      // }

      // Add handling for Asset Make Model match field
      FormModel? assetMakeModelField;
      FormModel? ifNoMatchField;

      // Find the Asset Make Model field and its dependent field
      for (var field in _allFormFields!) {
        if (field.recordType != 'PDAV') continue;

        if (field.apiName == 'Confirm_Asset_Make_Model__c') {
          assetMakeModelField = field;
        } else if (field.apiName == 'If_No_Match_mention_the_mismatched__c') {
          ifNoMatchField = field;
        }

        // If we found both fields, we can stop searching
        if (assetMakeModelField != null && ifNoMatchField != null) {
          break;
        }
      }

      // If we found both fields, apply the conditional logic
      if (assetMakeModelField != null &&
          ifNoMatchField != null &&
          assetMakeModelField.value != null) {
        // Enable the "If No Match" field only when "No Match" is selected
        ifNoMatchField.editable = (assetMakeModelField.value == 'No Match');
        ifNoMatchField.isRequired = (assetMakeModelField.value == 'No Match');

        // If making non-editable, clear the value
        if (!ifNoMatchField.editable) {
          ifNoMatchField.value = '';
        }

        // print(
        //     'Initialized If_No_Match_mention_the_mismatched__c: Editable = ${ifNoMatchField.editable}');
      }

      // 4. Handle Assigned_To__c field to control ARM-specific fields
      if (assignedToField != null) {
        final assignedTo = assignedToField.value?.toString() ?? '';
        bool isAssignedToRCUVendor = assignedTo == 'Assigned to RCU Vendor';
        bool isAssignedToRCUARM = assignedTo == 'Assigned to RCU ARM';

        // List of ARM-specific fields
        List<String> armSpecificFields = [
          'ARM_remarks_Non_discrepant_Discrepant__c',
          'Remarks_by_ARM__c',
          'ARM_OUTCOME_SUB_REASON__c'
        ];

        // List of fields that should always be disabled regardless of assignment
        List<String> alwaysDisabledFields = [
          'DM_ZM_remarks__c',
          'DM_ZM_OUTCOME_SUB_REASON__c'
        ];

        // Update ARM-specific fields based on assignment
        for (var field in _allFormFields!) {
          // Skip if not a PDAV field
          if (field.recordType != 'PDAV') continue;

          // For ARM-specific fields
          if (armSpecificFields.contains(field.apiName)) {
            // Enable only if assigned to RCU ARM
            field.editable = isAssignedToRCUARM;

            // Clear value if field is disabled and assignment changed to Vendor
            if (!field.editable && isAssignedToRCUVendor) {
              field.value = '';
            }

            // print(
            //     'Updated ARM field ${field.apiName}: Editable = ${field.editable}');
          }

          // For always disabled fields (DM/ZM fields)
          if (alwaysDisabledFields.contains(field.apiName)) {
            // Always keep these fields disabled
            field.editable = false;
            // print(
            //     'Disabled DM/ZM field ${field.apiName}: Editable = ${field.editable}');
          }
        }
      }
    }

    // Handle BPM_Appraisal form initialization
    if (isBPMAppraisalForm) {
      // For each trigger field, update its dependent field based on current value
      bpmTriggerFields.forEach((triggerApiName, triggerField) {
        String dependentFieldApiName = bpmDependentFieldMap[triggerApiName]!;

        // Find dependent field
        for (var field in _allFormFields!) {
          if (field.apiName == dependentFieldApiName &&
              field.recordType == 'BPM_Appraisal') {
            // Set required status based on trigger field's current value
            field.isRequired = (triggerField.value == 'No');
            break;
          }
        }
      });
    }
  }

  // Method for handling customer address traceability changes
  static void updateCustomerAddressTraceability(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

    // Find the customer address field and update its value
    FormModel? customerAddressField;

    for (var field in _allFormFields!) {
      if (field.apiName == 'Is_the_customer_s_address_traceable__c') {
        customerAddressField = field;
        field.value = newValue;
        field.isRequired = true; // Always required
        break;
      }
    }

    if (customerAddressField == null) return;

    // Update the dependent fields based on the new value
    for (var field in _allFormFields!) {
      // Handle the "If No" field - should be enabled only when address is NOT traceable
      if (field.recordType == 'PDAV' &&
          field.apiName == 'If_No_Need_to_co_ordinate_escalated_to__c') {
        // Enable only if address is not traceable (No)
        field.editable = (newValue == 'No');
        field.isRequired = (newValue == 'No');

        // If making non-editable, clear the value
        if (!field.editable) {
          field.value = '';
        }

        // print(
        //     'Updated If_No_Need_to_co_ordinate_escalated_to__c: Editable = ${field.editable}');
      }

      // Handle the "If Yes" field - should be enabled only when address IS traceable
      if (field.recordType == 'PDAV' &&
          field.apiName == 'If_Yes_capture_image_of_the_house__c') {
        // Enable only if address is traceable (Yes)
        field.editable = (newValue == 'Yes');
        field.isRequired = (newValue == 'Yes');
        // If making non-editable, clear the value
        if (!field.editable) {
          field.value = '';
        }

        // print(
        //     'Updated If_Yes_capture_image_of_the_house__c: Editable = ${field.editable}');
      }
    }

    // Refresh UI aggressively
    if (context.mounted) {
      // Force a rebuild of the UI
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (context is Element) {
            // Mark this element for rebuild
            context.markNeedsBuild();

            // Also mark ancestors for rebuild to ensure the entire form updates

            context.visitAncestorElements((ancestor) {
              ancestor.markNeedsBuild();
              return true;
            });
          }

          // Force a frame to be scheduled
          WidgetsBinding.instance.scheduleFrame();

          // For really stubborn UI updates, we can use this more aggressive approach
          if (formKey.currentState != null) {
            Future.microtask(() {
              if (formKey.currentContext != null) {
                (formKey.currentContext as Element).markNeedsBuild();
              }
            });
          }
        } catch (e) {
          print(
              'Error updating UI after customer address traceability change: $e');
        }
      });
    }
  }

  // Method for handling insurance certificate changes
  static void updateInsuranceCertificateRequirements(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

    // Find the insurance certificate field and update its value
    FormModel? insuranceCertificateField;

    for (var field in _allFormFields!) {
      if (field.apiName == 'Insurance_Certificate_received__c') {
        insuranceCertificateField = field;
        field.value = newValue;
        break;
      }
    }

    if (insuranceCertificateField == null) return;

    // Fields to enable if insurance certificate is NOT received
    List<String> enabledIfNoInsurance = [
      // 'If_No__c',
      // 'If_asset_not_seen_at_the_time_of_village__c',
      // 'If_asset_not_seen_at_the_time_of_visit__c',
      // 'Asset_available_with_whom__c',
      // 'If_third_party_take_details__c',
      // 'Confirm_Asset_Make_Model__c',
      // 'If_No_Match_mention_the_mismatched__c',
      // 'RC_received_If_yes_please_share_RC_no_2__c',
      // 'If_No_mention_the_reason__c'
    ];

    // Update field requirements based on insurance certificate status
    for (var field in _allFormFields!) {
      // Skip if not a PDAV field
      if (field.recordType != 'PDAV') continue;

      // Enable specified fields only if insurance certificate is not received
      if (enabledIfNoInsurance.contains(field.apiName)) {
        field.editable = (newValue == 'No');
        field.isRequired = (newValue == 'No');

        // If making non-editable, clear the value
        if (!field.editable) {
          field.value = '';
        }

        // print('Updated ${field.apiName}: Editable = ${field.editable}');
      }
    }

    // Refresh UI aggressively
    if (context.mounted) {
      // Force immediate rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (context is Element) {
            // Mark this element for rebuild
            context.markNeedsBuild();

            // Also mark ancestors for rebuild to ensure the entire form updates
            context.visitAncestorElements((ancestor) {
              ancestor.markNeedsBuild();
              return true;
            });
          }

          // Force a frame to be scheduled
          WidgetsBinding.instance.scheduleFrame();

          // For really stubborn UI updates, we can use this more aggressive approach
          if (formKey.currentState != null) {
            Future.microtask(() {
              if (formKey.currentContext != null) {
                (formKey.currentContext as Element).markNeedsBuild();
              }
            });
          }
        } catch (e) {
          print('Error updating UI after insurance certificate change: $e');
        }
      });
    }
  }

  // Add method to handle asset make model match field
  static void updateAssetMakeModelMatch(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

    // print('Updating Asset Make Model match: $newValue');

    // Find the "If No Match" field that needs to be toggled based on selection
    FormModel? ifNoMatchField;

    // Find the field
    for (var field in _allFormFields!) {
      if (field.recordType != 'PDAV') continue;

      if (field.apiName == 'If_No_Match_mention_the_mismatched__c') {
        ifNoMatchField = field;
        break;
      }
    }

    // If we found the field, update its editable state based on selection
    if (ifNoMatchField != null) {
      // Enable the field only if "No Match" is selected
      ifNoMatchField.editable = (newValue == 'No Match');
      ifNoMatchField.isRequired = (newValue == 'No Match');

      // If making non-editable, clear the value
      if (!ifNoMatchField.editable) {
        ifNoMatchField.value = '';
      }

      // print(
      //     'Updated If_No_Match_mention_the_mismatched__c: Editable = ${ifNoMatchField.editable}');
    }

    // Refresh UI to show updated fields
    if (context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (context is Element) {
            // Mark this element for rebuild
            context.markNeedsBuild();

            // Also mark ancestors for rebuild to ensure the entire form updates
            context.visitAncestorElements((ancestor) {
              ancestor.markNeedsBuild();
              return true;
            });
          }

          // Force a frame to be scheduled
          WidgetsBinding.instance.scheduleFrame();

          // For really stubborn UI updates, use this more aggressive approach
          if (formKey.currentState != null) {
            Future.microtask(() {
              if (formKey.currentContext != null) {
                (formKey.currentContext as Element).markNeedsBuild();
              }
            });
          }
        } catch (e) {
          print('Error updating UI after asset make model match change: $e');
        }
      });
    }
  }

  // Fix the updateAssetVisibilityRequirements method
  static void updateAssetVisibilityRequirements(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

    // Find the asset seen field and update its value
    FormModel? assetSeenField;

    for (var field in _allFormFields!) {
      if (field.apiName == 'Is_the_Asset_seen_at_the_time_of_visit__c') {
        assetSeenField = field;
        field.value = newValue;
        field.isRequired = true; // Always required
        break;
      }
    }

    if (assetSeenField == null) return;

    // Fields to enable if asset is seen
    List<String> enabledIfSeen = [
      'Actual_Asset_Make_Model__c',
      'Does_asset_make_model_match_with_system__c',
      'Does_Asset_Registration_number_match__c',
      'Engine_number_as_per_vehicle_seen__c',
      'Chassis_number_as_per_vehicle_seen__c',
      'Do_the_details_in_INVOICE_matches__c',
      'RC_received_If_yes_please_share_RC_no__c',
      'If_No_mention_the_reason_PDAV__c',
      'Insurance_Certificate_received__c'
    ];

    // Fields to enable if asset is not seen
    List<String> enabledIfNotSeen = [
      'If_asset_not_seen_at_the_time_of_village__c',
      'If_asset_not_seen_at_the_time_of_visit__c',
      'Asset_available_with_whom__c',
      'If_third_party_take_details__c'
    ];

    // Update field requirements based on new asset visibility value
    for (var field in _allFormFields!) {
      // Special handling for the two fields that should always be enabled
      // if (field.apiName == 'If_No_mention_the_reason_PDAV__c' ||
      //     field.apiName == 'Insurance_Certificate_received__c') {
      //   // Keep these fields always enabled but mark as required only when asset is seen
      //   field.isRequired = (newValue == 'Yes');
      //   field.editable = true; // Always enabled
      //   continue; // Skip further processing for these fields
      // }

      // For fields that should be enabled
      field.isRequired = true; // Always requiredif asset is seen
      if (enabledIfSeen.contains(field.apiName)) {
        field.isRequired = (newValue == 'Yes');
        field.editable = (newValue == 'Yes');

        // If making non-editable, clear the value
        if (!field.editable) {
          field.value = '';
        }
      }

      // For fields that should be enabled if asset is NOT seen
      if (enabledIfNotSeen.contains(field.apiName)) {
        field.isRequired = (newValue == 'No');
        field.editable = (newValue == 'No');

        // If making non-editable, clear the value
        if (!field.editable) {
          field.value = '';
        }
      }
    }

    // Refresh UI aggressively
    if (context.mounted) {
      // Force immediate rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (context is Element) {
            // Mark this element for rebuild
            context.markNeedsBuild();

            // Also mark ancestors for rebuild to ensure the entire form updates
            context.visitAncestorElements((ancestor) {
              ancestor.markNeedsBuild();
              return true;
            });
          }

          // Force a frame to be scheduled
          WidgetsBinding.instance.scheduleFrame();

          // For really stubborn UI updates, we can use this more aggressive approach
          if (formKey.currentState != null) {
            Future.microtask(() {
              if (formKey.currentContext != null) {
                (formKey.currentContext as Element).markNeedsBuild();
              }
            });
          }
        } catch (e) {
          // print('Error updating UI after asset visibility change: $e');
        }
      });
    }
  }

  // Add this method to FormModel class
  Widget getLabelWidget() {
    // Check if this field is a conditional field
    bool isConditionalField = false;

    // Lists of conditional fields for PDAV
    List<String> mandatoryIfSeen = [
      'Actual_Asset_Make_Model__c',
      'Does_asset_make_model_match_with_system__c',
      'Does_Asset_Registration_number_match__c',
      'Engine_number_as_per_vehicle_seen__c',
      'Chassis_number_as_per_vehicle_seen__c',
      'Do_the_details_in_INVOICE_matches__c',
      'RC_received_If_yes_please_share_RC_no__c',
      'If_No_mention_the_reason_PDAV__c',
      'Insurance_Certificate_received__c'
    ];

    List<String> mandatoryIfNotSeen = [
      'If_asset_not_seen_at_the_time_of_village__c',
      'If_asset_not_seen_at_the_time_of_visit__c',
      'Asset_available_with_whom__c',
      'If_third_party_take_details__c'
    ];

    // List of conditional fields for BPM_Appraisal
    List<String> bpmConditionalFields = [
      'If_no_Mention_Lan__c',
      'If_no_Mention_Lan1__c',
      'If_no_Mention_Lan2__c'
    ];

    // Check if this is a conditional field
    if (recordType == 'PDAV') {
      isConditionalField = (mandatoryIfSeen.contains(apiName) ||
          mandatoryIfNotSeen.contains(apiName));
    } else if (recordType == 'BPM_Appraisal') {
      isConditionalField = bpmConditionalFields.contains(apiName);
    }

    // Get field state for visualization
    bool isConditionalMandatory = isConditionalField && isRequired;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isRequired ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
        if (isConditionalMandatory)
          Text(
            ' *Required',
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  // Add this method to the FormModel class to calculate the date difference
  static void updateDateDifferenceForCrossAudit(
      BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

    // Check if this is a Cross_Audit form
    bool isCrossAuditForm = false;
    FormModel? fromDateField;
    FormModel? toDateField;
    FormModel? daysDifferenceField;

    for (var field in _allFormFields!) {
      if (field.recordType == 'Cross_Audit') {
        isCrossAuditForm = true;
        // print('It is a cross audit');
        // Find the relevant fields
        if (field.apiName == 'From_Date__c') {
          fromDateField = field;
        } else if (field.apiName == 'To_Date__c') {
          toDateField = field;
        } else if (field.apiName == 'Days_Audit_Carried_To_date_From_Date__c') {
          daysDifferenceField = field;
        }
      }
    }

    // If not a Cross_Audit form or missing fields, return early
    if (!isCrossAuditForm) {
      return;
    }

    // If the days difference field doesn't exist, look for it by record type
    if (daysDifferenceField == null) {
      for (var field in _allFormFields!) {
        if (field.recordType == 'Cross_Audit' &&
            field.apiName == 'Days_Audit_Carried_To_date_From_Date__c') {
          daysDifferenceField = field;
          break;
        }
      }
    }

    // If we found both date fields
    if (fromDateField != null && toDateField != null) {
      String? fromDateStr = fromDateField.value;
      String? toDateStr = toDateField.value;

      // Only calculate if both dates are set
      if (fromDateStr != null &&
          fromDateStr.isNotEmpty &&
          toDateStr != null &&
          toDateStr.isNotEmpty) {
        try {
          // Parse dates (handle different possible formats)
          DateTime fromDate;
          DateTime toDate;

          try {
            // Try yyyy-MM-dd format first
            fromDate = DateFormat('yyyy-MM-dd').parse(fromDateStr);
          } catch (e) {
            // Fall back to other common formats
            fromDate = DateFormat('dd/MM/yyyy').parse(fromDateStr);
          }

          try {
            // Try yyyy-MM-dd format first
            toDate = DateFormat('yyyy-MM-dd').parse(toDateStr);
          } catch (e) {
            // Fall back to other common formats
            toDate = DateFormat('dd/MM/yyyy').parse(toDateStr);
          }

          // Calculate difference in days
          int difference = toDate.difference(fromDate).inDays;

          // Update the display field if it exists
          if (daysDifferenceField != null) {
            daysDifferenceField.value = '$difference';
            // Make the field non-editable
            daysDifferenceField.editable = false;
            // print(
            //     'Date difference calculated for Cross_Audit: $difference days');
            // print('Made Days_Audit_Carried_To_date_From_Date__c non-editable');
          } else {
            // If the field doesn't exist, create it as non-editable
            FormModel newField = FormModel(
              type:
                  'ReadOnly', // Use ReadOnly type to ensure it's never editable
              label: 'Days Difference',
              editable: false, // Explicitly set to non-editable
              apiName: 'Days_Audit_Carried_To_date_From_Date__c',
              pageType: 'Form',
              value: '$difference days',
              isRequired: false,
              recordType: 'Cross_Audit',
            );
            _allFormFields!.add(newField);
          }
        } catch (e) {
          // print('Error calculating date difference: $e');
          // Set an error message in the field
          if (daysDifferenceField != null) {
            daysDifferenceField.value = 'Invalid dates';
            // Make sure it's still non-editable even if calculation fails
            daysDifferenceField.editable = false;
          }
        }
      } else {
        // If either date is missing, clear the difference
        if (daysDifferenceField != null) {
          daysDifferenceField.value = '';
          // Keep it non-editable
          daysDifferenceField.editable = false;
        }
      }
    }

    // Force UI refresh to show the updated value
    if (context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (context is Element) {
            context.markNeedsBuild();

            // Also mark ancestors for rebuild
            context.visitAncestorElements((ancestor) {
              ancestor.markNeedsBuild();
              return true;
            });
          }

          // Force a frame
          WidgetsBinding.instance.scheduleFrame();

          // For really stubborn UI updates, use this more aggressive approach
          if (formKey.currentState != null) {
            Future.microtask(() {
              if (formKey.currentContext != null) {
                (formKey.currentContext as Element).markNeedsBuild();
              }
            });
          }
        } catch (e) {
          // print('Error updating UI after date difference calculation: $e');
        }
      });
    }
  }

  // Add a new method to handle Collection_Audit Status field changes
  static void updateCollectionAuditStatus(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

    // print('Updating Collection Audit status: $newValue');

    // Fields to be non-required if status is "Visited"
    List<String> nonRequiredIfVisited = [
      'If_not_visited__c',
      'Approval_taken_for_on_behalf_collection__c'
    ];

    // Update field requirements based on status
    for (var field in _allFormFields!) {
      // Skip if not a Collection_Audit field
      if (field.recordType != 'Collection_Audit') continue;

      // For fields that should not be required if status is "Visited"
      if (nonRequiredIfVisited.contains(field.apiName)) {
        field.isRequired = (newValue != 'Visited');
        field.editable = (newValue != 'Visited');
        // print(
        //     'Updated field ${field.apiName}: Required = ${field.isRequired}, Status = $newValue');
      }
    }

    // Refresh UI to show updated requirements
    if (context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (context is Element) {
            // Mark this element for rebuild
            context.markNeedsBuild();

            // Also mark ancestors for rebuild to ensure the entire form updates
            context.visitAncestorElements((ancestor) {
              ancestor.markNeedsBuild();
              return true;
            });
          }

          // Force a frame to be scheduled
          WidgetsBinding.instance.scheduleFrame();

          // For really stubborn UI updates, use this more aggressive approach
          if (formKey.currentState != null) {
            Future.microtask(() {
              if (formKey.currentContext != null) {
                (formKey.currentContext as Element).markNeedsBuild();
              }
            });
          }
        } catch (e) {
          print('Error updating UI after Collection Audit status change: $e');
        }
      });
    }
  }

  // Add this method to form_model.dart
  static void _initCrossAuditDateDifference(
      BuildContext? context, GlobalKey<FormState>? formKey) {
    if (_allFormFields == null || context == null || formKey == null) {
      return;
    }

    // Check if this is a Cross_Audit form
    bool isCrossAuditForm = false;
    for (var field in _allFormFields!) {
      if (field.recordType == 'Cross_Audit') {
        isCrossAuditForm = true;
        break;
      }
    }

    if (isCrossAuditForm) {
      // Find the From_Date__c and To_Date__c fields
      FormModel? fromDateField;
      FormModel? toDateField;

      for (var field in _allFormFields!) {
        if (field.recordType == 'Cross_Audit') {
          if (field.apiName == 'From_Date__c') {
            fromDateField = field;
          } else if (field.apiName == 'To_Date__c') {
            toDateField = field;
          }
        }
      }

      // If both date fields have values, calculate the difference
      if (fromDateField != null &&
          fromDateField.value != null &&
          toDateField != null &&
          toDateField.value != null) {
        // Calculate the date difference
        updateDateDifferenceForCrossAudit(context, formKey);
      }

      // Find the days difference field and make sure it's not editable
      FormModel? daysDifferenceField;
      for (var field in _allFormFields!) {
        if (field.apiName == 'Days_Audit_Carried_To_date_From_Date__c') {
          daysDifferenceField = field;
          // Ensure this field is not editable
          daysDifferenceField.editable = false;
          break;
        }
      }
    }
  }

  // Add method to handle PDAV loan relationship fields
  static void updateCollectionAuditLoanRelationship(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

    // print('Updating PDAV loan relationship: $newValue');

    FormModel? relativeDetailsField;
    FormModel? thirdPartyDetailsField;

    // Find the two related fields that need to be toggled
    for (var field in _allFormFields!) {
      // Only look in PDAV record type
      if (field.recordType != 'PDAV') continue;

      if (field.apiName == 'If_Relative_mention_details__c') {
        relativeDetailsField = field;
      } else if (field.apiName == 'If_Third_Party_mention_details__c') {
        thirdPartyDetailsField = field;
      }

      // If we found both fields, we can stop searching
      if (relativeDetailsField != null && thirdPartyDetailsField != null) {
        break;
      }
    }

    // Update the fields based on the selected value
    if (relativeDetailsField != null && thirdPartyDetailsField != null) {
      // print('Current selection for loan relationship: $newValue');

      if (newValue == 'Relative') {
        // If "Relative" is selected, enable relative details field and disable third party details
        relativeDetailsField.editable = true;
        thirdPartyDetailsField.editable = false;
        // Clear the third party field value since it's now disabled
        thirdPartyDetailsField.value = null;
        // print(
        //     'Enabled Relative details field, disabled Third Party details field');
      } else if (newValue == 'Third Party') {
        // If "Third Party" is selected, enable third party details field and disable relative details
        relativeDetailsField.editable = false;
        thirdPartyDetailsField.editable = true;
        // Clear the relative field value since it's now disabled
        relativeDetailsField.value = null;
        // print(
        //     'Enabled Third Party details field, disabled Relative details field');
      } else {
        // For any other selection (like "Self" or null), disable both fields
        relativeDetailsField.editable = false;
        thirdPartyDetailsField.editable = false;
        // Clear both field values
        relativeDetailsField.value = null;
        thirdPartyDetailsField.value = null;
        // print('Disabled both Relative and Third Party details fields');
      }
    }

    // Refresh UI to show updated fields
    if (context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (context is Element) {
            // Mark this element for rebuild
            context.markNeedsBuild();

            // Also mark ancestors for rebuild to ensure the entire form updates
            context.visitAncestorElements((ancestor) {
              ancestor.markNeedsBuild();
              return true;
            });
          }

          // Force a frame to be scheduled
          WidgetsBinding.instance.scheduleFrame();

          // For really stubborn UI updates, use this more aggressive approach
          if (formKey.currentState != null) {
            Future.microtask(() {
              if (formKey.currentContext != null) {
                (formKey.currentContext as Element).markNeedsBuild();
              }
            });
          }
        } catch (e) {
          print(
              'Error updating UI after Collection Audit loan relationship change: $e');
        }
      });
    }
  }

  // Add this method to handle BPM_Appraisal conditional field requirements
  static void updateBPMAppraisalRequirements(
      String? newValue,
      String triggerFieldApiName,
      BuildContext context,
      GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

    // Define mappings of trigger fields to their dependent fields
    Map<String, String> dependentFieldMap = {
      'Did_BPM_visited_all_residence_of_borrowe__c': 'If_no_Mention_Lan__c',
      'Did_BPM_verified_all_documents_of_borrow__c': 'If_no_Mention_Lan1__c',
      'Did_BPM_verified_Borrowers_Bank_Passbook__c': 'If_no_Mention_Lan2__c',
    };

    // If this is one of our trigger fields
    if (dependentFieldMap.containsKey(triggerFieldApiName)) {
      String dependentFieldApiName = dependentFieldMap[triggerFieldApiName]!;

      // Find the dependent field
      FormModel? dependentField;
      for (var field in _allFormFields!) {
        if (field.apiName == dependentFieldApiName &&
            field.recordType == 'BPM_Appraisal') {
          dependentField = field;
          break;
        }
      }

      // Update the dependent field's required status based on the trigger field value
      if (dependentField != null) {
        bool shouldBeRequired = (newValue == 'No');
        // print(
        //     'Updating BPM_Appraisal field ${dependentField.apiName}: Required = $shouldBeRequired');
        dependentField.isRequired = shouldBeRequired;

        // Refresh UI to reflect the change
        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              if (context is Element) {
                context.markNeedsBuild();
                context.visitAncestorElements((ancestor) {
                  ancestor.markNeedsBuild();
                  return true;
                });
              }

              WidgetsBinding.instance.scheduleFrame();

              if (formKey.currentState != null) {
                Future.microtask(() {
                  if (formKey.currentContext != null) {
                    (formKey.currentContext as Element).markNeedsBuild();
                  }
                });
              }
            } catch (e) {
              print('Error updating UI after BPM_Appraisal field change: $e');
            }
          });
        }
      }
    }
  }

  // Method for handling assignment changes for PDAV record type
  static void updateAssignmentStatus(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

    // Determine assignment type
    bool isAssignedToRCUVendor = newValue == 'Assigned to RCU Vendor';
    bool isAssignedToRCUARM = newValue == 'Assigned to RCU ARM';

    // List of ARM-specific fields
    List<String> armSpecificFields = [
      'ARM_remarks_Non_discrepant_Discrepant__c',
      'Remarks_by_ARM__c',
      'ARM_OUTCOME_SUB_REASON__c'
    ];

    // Update ARM-specific fields based on assignment
    for (var field in _allFormFields!) {
      // Skip if not a PDAV field
      if (field.recordType != 'PDAV') continue;

      // For ARM-specific fields
      if (armSpecificFields.contains(field.apiName)) {
        // Enable only if assigned to RCU ARM
        field.editable = isAssignedToRCUARM;

        // Clear value if field is disabled and assignment changed to Vendor
        if (!field.editable && isAssignedToRCUVendor) {
          field.value = '';
        }

        // print(
        //     'Updated ARM field ${field.apiName} due to assignment change: Editable = ${field.editable}');
      }
    }

    // Refresh UI aggressively to reflect changes
    if (context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          // Force rebuild of the whole widget tree
          if (context is Element) {
            context.markNeedsBuild();
            context.visitAncestorElements((ancestor) {
              ancestor.markNeedsBuild();
              return true;
            });
          }

          // Try rebuilding the form specifically
          if (formKey.currentState != null) {
            (formKey.currentState as dynamic).setState(() {});
          }

          // Schedule a frame to ensure changes are visible
          WidgetsBinding.instance.scheduleFrame();

          // print('UI refresh triggered for assignment change to: $newValue');
        } catch (e) {
          print('Error refreshing UI after assignment change: $e');
        }
      });
    }
  }

  // Method to handle If_not_disbursed__c field changes for Live_Disbursement record type
  static void updateNotDisbursedReason(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

    // Find the If_not_disbursed__c field and update its value
    FormModel? notDisbursedField;

    for (var field in _allFormFields!) {
      if (field.apiName == 'If_not_disbursed__c' &&
          field.recordType == 'Live_Disbursement') {
        notDisbursedField = field;
        field.value = newValue;
        break;
      }
    }

    if (notDisbursedField == null) return;

    // Update the If_others_then__c field based on the new value
    for (var field in _allFormFields!) {
      if (field.recordType == 'Live_Disbursement' &&
          field.apiName == 'If_others_then__c') {
        // Enable and require only if reason is 'others'
        bool shouldBeEditableAndRequired =
            (newValue?.toLowerCase() == 'others');
        field.editable = shouldBeEditableAndRequired;
        field.isRequired = shouldBeEditableAndRequired;

        // If making non-editable, clear the value
        if (!field.editable) {
          field.value = '';
        }

        // print(
        //     'Updated If_others_then__c: Editable = ${field.editable}, Required = ${field.isRequired}');
        break;
      }
    }

    // Refresh UI aggressively
    if (context.mounted) {
      // Force immediate rebuild
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (context is Element) {
            // Mark this element for rebuild
            context.markNeedsBuild();

            // Also mark ancestors for rebuild to ensure the entire form updates
            context.visitAncestorElements((ancestor) {
              ancestor.markNeedsBuild();
              return true;
            });
          }

          // Force a frame to be scheduled
          WidgetsBinding.instance.scheduleFrame();

          // For really stubborn UI updates, we can use this more aggressive approach
          if (formKey.currentState != null) {
            Future.microtask(() {
              if (formKey.currentContext != null) {
                (formKey.currentContext as Element).markNeedsBuild();
              }
            });
          }
        } catch (e) {
          print('Error updating UI after not disbursed reason change: $e');
        }
      });
    }
  }

  // Method for handling RC_received__c field changes
  static void updateRCReceivedStatus(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) return;

    // print('Updating RC received status: $newValue');

    // Update RC number field based on RC received status
    for (var field in _allFormFields!) {
      if (field.recordType != 'PDAV') continue;

      // Handle RC number field
      if (field.apiName == 'If_yes_please_share_RC_number__c') {
        field.editable = (newValue == 'Yes');
        field.isRequired = (newValue == 'Yes');

        if (!field.editable) {
          field.value = ''; // Clear value when disabled
        }
        // print(
        //     'Updated If_yes_please_share_RC_number__c: Editable = ${field.editable}');
      }

      // Handle reason field
      if (field.apiName == 'If_No_mention_the_reason__c') {
        field.editable = (newValue == 'No');
        field.isRequired = (newValue == 'No');

        if (!field.editable) {
          field.value = ''; // Clear value when disabled
        }
        // print(
        //     'Updated If_No_mention_the_reason_PDAV__c: Editable = ${field.editable}');
      }
    }

    // Refresh UI to show updated fields
    _refreshUI(context, formKey);
  }

// Method for handling Local_or_OGL_Pick__c field changes
  static void updateOGLStatus(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) return;

    // print('Updating OGL status: $newValue');

    // Update OGL km field based on OGL selection
    for (var field in _allFormFields!) {
      if (field.recordType != 'PDAV') continue;

      if (field.apiName == 'If_OGL_mention_Kms__c') {
        field.editable = (newValue == 'OGL');
        field.isRequired = (newValue == 'OGL');

        if (!field.editable) {
          field.value = ''; // Clear value when disabled
        }
        // print('Updated If_OGL_mention_Kms__c: Editable = ${field.editable}');
      }
    }

    // Refresh UI to show updated fields
    _refreshUI(context, formKey);
  }

// Helper method to refresh UI after field updates
  static void _refreshUI(BuildContext context, GlobalKey<FormState> formKey) {
    if (context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (context is Element) {
            context.markNeedsBuild();
            context.visitAncestorElements((ancestor) {
              ancestor.markNeedsBuild();
              return true;
            });
          }
          WidgetsBinding.instance.scheduleFrame();

          if (formKey.currentState != null && formKey.currentContext != null) {
            Future.microtask(() {
              (formKey.currentContext as Element).markNeedsBuild();
            });
          }
        } catch (e) {
          print('Error refreshing UI: $e');
        }
      });
    }
  }
}
