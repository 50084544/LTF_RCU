import 'package:BMS/core/network/api_service.dart';
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
  bool isRequired;
  List<String>? picklistValues;

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
  static void setFormFields(List<FormModel> fields) {
    _allFormFields = fields;

    // Check if Live_Disbursement form with Disbursal Status field exists
    _checkForDisbursalStatusField();

    // Check if PDAV form with asset visibility field exists
    _updatePDAVFieldsVisibility();
  }

  // Method to handle Disbursal Status field changes
  static void updateDisbursalStatus(String? newStatus) {
    if (disbursalStatus == newStatus) return; // No change

    disbursalStatus = newStatus;

    if (_allFormFields == null) return;

    bool foundDisbursalStatusField = false;
    bool makeReadOnly = disbursalStatus == 'Not disbursed';

    // Process fields after Disbursal Status field
    for (var field in _allFormFields!) {
      // Once we find the Disbursal Status field, mark it so we know to process subsequent fields
      if (field.apiName == 'Disbursal_Status__c') {
        foundDisbursalStatusField = true;
        continue; // Skip this field itself
      }

      // Make all fields after the Disbursal Status field read-only if "Not disbursed" is selected
      if (foundDisbursalStatusField) {
        // Store original editable value if we haven't done so
        if (field.apiName == 'If_others_then__c') {
          // Keep "If others then" field always editable
          continue; // Skip making this field read-only
        }

        field.editable =
            makeReadOnly ? false : (field.isRequired || field.editable);
      }
    }
  }

  // Check if this is a Live_Disbursement form and initialize Disbursal Status if found
  static void _checkForDisbursalStatusField() {
    if (_allFormFields == null) return;

    FormModel? disbursalStatusField;

    // Find the Disbursal Status field
    for (var field in _allFormFields!) {
      if (field.apiName == 'Disbursal_Status__c') {
        disbursalStatusField = field;
        break;
      }
    }

    // If we found the field, initialize its status
    if (disbursalStatusField != null) {
      updateDisbursalStatus(disbursalStatusField.value);
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

    for (var field in _allFormFields!) {}

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
    List<String> updatedFieldLabels = [];

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

  // Update the handleReferenceApiResponse method
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
            referenceData.forEach((key, value) {});

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

              // Update form fields with values from the processed API response
              updateFormFieldsFromApiResponse(processedData, context,
                  referenceFieldLabel: referenceFieldLabel);

              // Set success flag to show appropriate message
              success = true;
              message = 'Details fetched successfully!';
            } else {
              // Fall back to original data if form fields are not set
              referenceData.forEach((key, value) {
                processedData[key] = value;
              });
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

      case 'ReadOnly':
        // Use ValueListenable to ensure the UI updates when the value changes
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            getLabelWidget(), // Use getLabelWidget instead of Text
            const SizedBox(height: 4),
            StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                // Create a unique key for this container to force rebuild
                return Container(
                  key: ValueKey(
                      'readonly_${label}_${value}_${DateTime.now().millisecondsSinceEpoch}'),
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[
                        300], // Use same grey as other non-editable fields
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: Colors.grey[500]!), // Match the border color
                  ),
                  child: Text(
                    value ?? '',
                    style: getTextStyle(), // Use the same text style
                  ),
                );
              },
            ),
          ],
        );
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

      case 'REFERENCE':
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
              value: value?.isNotEmpty == true
                  ? value // If there's a value from API, use it
                  : null, // Otherwise use null to show "Select an option"
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
              onChanged: isReadOnly
                  ? null
                  : (val) {
                      if (val != null) {
                        // Store the previous value
                        String? previousValue = value;

                        // Update value
                        value = val;

                        // Special handling for Disbursal Status field
                        if (apiName == 'Disbursal_Status__c') {
                          FormModel.updateDisbursalStatus(val);
                        }

                        // Special handling for Asset visibility field in PDAV
                        if (apiName ==
                            'Is_the_Asset_seen_at_the_time_of_visit__c') {
                          // print(
                          //     'Asset visibility changed from $previousValue to $val');
                          FormModel.updateAssetVisibilityRequirements(
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
                    },
              validator: (val) {
                if (isRequired && editable && (val == null)) {
                  return '$label is required';
                }
                return null;
              },
            ),
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
                FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
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
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
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
              if (type != 'Text')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Field type: $type',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
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

    for (var field in _allFormFields!) {
      if (field.recordType == 'PDAV') {
        isPDAVForm = true;
        break; // We've confirmed it's a PDAV form, no need to check further
      }
    }

    // If not a PDAV form, return early
    if (!isPDAVForm) {
      return;
    }

    // Find the asset seen field
    for (var field in _allFormFields!) {
      if (field.apiName == 'Is_the_Asset_seen_at_the_time_of_visit__c') {
        assetSeenField = field;
        break;
      }
    }

    // If asset seen field not found, return
    if (assetSeenField == null) {
      return;
    }

    // Get the selected value of the asset seen field
    final assetSeen = assetSeenField.value;

    // Fields to be mandatory if asset is seen
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

    // Fields to be mandatory if asset is not seen
    List<String> mandatoryIfNotSeen = [
      'If_asset_not_seen_at_the_time_of_village__c',
      'If_asset_not_seen_at_the_time_of_visit__c',
      'Asset_available_with_whom__c',
      'If_third_party_take_details__c'
    ];

    // Update field requirements based on asset visibility
    for (var field in _allFormFields!) {
      // Skip if not a PDAV field
      if (field.recordType != 'PDAV') continue;

      // For fields that should be mandatory if asset is seen
      if (mandatoryIfSeen.contains(field.apiName)) {
        field.isRequired = (assetSeen == 'Yes');
        // Debug print to verify changes
        print(
            'Field ${field.apiName}: Required = ${field.isRequired}, AssetSeen = $assetSeen');
      }

      // For fields that should be mandatory if asset is NOT seen
      if (mandatoryIfNotSeen.contains(field.apiName)) {
        field.isRequired = (assetSeen == 'No');
        // Debug print to verify changes
        // print(
        //     'Field ${field.apiName}: Required = ${field.isRequired}, AssetSeen = $assetSeen');
      }
    }
  }

  // Fix the updateAssetVisibilityRequirements method
  static void updateAssetVisibilityRequirements(
      String? newValue, BuildContext context, GlobalKey<FormState> formKey) {
    if (_allFormFields == null) {
      return;
    }

   // print('Updating asset visibility requirements: $newValue');

    // Find the asset seen field and update its value
    FormModel? assetSeenField;

    for (var field in _allFormFields!) {
      if (field.apiName == 'Is_the_Asset_seen_at_the_time_of_visit__c') {
        assetSeenField = field;

        // Update field value
        // print('Changing asset visibility from ${field.value} to $newValue');
        field.value = newValue;
        break;
      }
    }

    if (assetSeenField == null) return;

    // Fields to be mandatory if asset is seen
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

    // Fields to be mandatory if asset is not seen
    List<String> mandatoryIfNotSeen = [
      'If_asset_not_seen_at_the_time_of_village__c',
      'If_asset_not_seen_at_the_time_of_visit__c',
      'Asset_available_with_whom__c',
      'If_third_party_take_details__c'
    ];

    // Update field requirements based on new asset visibility value
    for (var field in _allFormFields!) {
      // Skip if not a PDAV field
      if (field.recordType != 'PDAV') continue;

      // For fields that should be mandatory if asset is seen
      if (mandatoryIfSeen.contains(field.apiName)) {
        field.isRequired = (newValue == 'Yes');
        // print(
        //     'Updated field ${field.apiName}: Required = ${field.isRequired}, AssetSeen = $newValue');
      }

      // For fields that should be mandatory if asset is NOT seen
      if (mandatoryIfNotSeen.contains(field.apiName)) {
        field.isRequired = (newValue == 'No');
        // print(
        //     'Updated field ${field.apiName}: Required = ${field.isRequired}, AssetSeen = $newValue');
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
              formKey.currentState?.setState(() {});
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
    // Check if this field is a conditional PDAV field
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

    // Check if this is a conditional PDAV field
    isConditionalField = (recordType == 'PDAV' &&
        (mandatoryIfSeen.contains(apiName) ||
            mandatoryIfNotSeen.contains(apiName)));

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
              formKey.currentState?.setState(() {});
            });
          }
        } catch (e) {
          // print('Error updating UI after date difference calculation: $e');
        }
      });
    }
  }
}
