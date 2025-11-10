import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
//import 'package:file_picker/file_picker.dart';
import 'package:sachet/features/form/data/datasources/form_service.dart';
import 'package:sachet/core/network/api_service.dart';
import 'package:lottie/lottie.dart';
import 'dart:convert';

class FileUploadSection extends StatefulWidget {
  final String workId;
  final int maxFiles;
  final bool enabled;

  const FileUploadSection({
    Key? key,
    required this.workId,
    this.maxFiles = 3,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<FileUploadSection> createState() => FileUploadSectionState();
}

// Make the state class public so it can be accessed by the form
class FileUploadSectionState extends State<FileUploadSection> {
  final List<FileUploadItem> _files = [];
  bool _isUploading = false;
  bool _uploadSuccess = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadExistingFiles();
  }

  Future<void> _loadExistingFiles() async {
    try {
      final formApiService = FormApiService();
      final uploadedFiles =
          await formApiService.getUploadedImagesForWorkId(widget.workId);

      if (uploadedFiles.isNotEmpty) {
        setState(() {
          _uploadSuccess = true;
        });
      }
    } catch (e) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_files.length >= widget.maxFiles) {
      _showMaxFilesReachedDialog();
      return;
    }

    try {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 80,
      );

      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final fileExt = pickedFile.name.split('.').last.toLowerCase();

      if (!['jpg', 'jpeg', 'png', 'pdf'].contains(fileExt)) {
        _showUnsupportedFileDialog();
        return;
      }

      setState(() {
        _files.add(FileUploadItem(
          file: file, // Make sure to pass the file
          name: pickedFile.name,
          type: 'image/${fileExt == 'jpg' ? 'jpeg' : fileExt}',
        ));
      });
    } catch (e) {
      _showErrorDialog('Failed to pick image');
    }
  }

  Future<void> _pickFile() async {
    if (_files.length >= widget.maxFiles) {
      _showMaxFilesReachedDialog();
      return;
    }

    try {
      // Use image_picker for files as well
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickMedia(
        imageQuality: 80,
        // No need to specify mediaType - it will show all files
      );

      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final fileExt = pickedFile.name.split('.').last.toLowerCase();

      if (fileExt == 'pdf') {
        setState(() {
          _files.add(FileUploadItem(
            file: file,
            name: pickedFile.name,
            type: 'application/pdf',
          ));
        });
      } else if (['jpg', 'jpeg', 'png'].contains(fileExt)) {
        setState(() {
          _files.add(FileUploadItem(
            file: file,
            name: pickedFile.name,
            type: 'image/${fileExt == 'jpg' ? 'jpeg' : fileExt}',
          ));
        });
      } else {
        _showUnsupportedFileDialog();
      }
    } catch (e) {
      _showErrorDialog('Failed to pick file');
    }
  }

  // Method to handle the upload process - to be called from the form submission
  Future<bool> uploadFiles() async {
    if (_files.isEmpty) {
      return true; // No files to upload is not an error
    }

    setState(() {
      _isUploading = true;
      _errorMessage = '';
    });

    try {
      // Prepare files for upload
      final List<Map<String, dynamic>> preparedFiles = await getFilesToUpload();

      if (preparedFiles.isEmpty) {
        setState(() {
          _isUploading = false;
          _errorMessage = 'No valid files to upload';
        });
        return false;
      }

      // Call API to upload files
      final apiCall = ApiCall();
      final result = await apiCall.callApi(
        endpoint: 'uploadimages',
        workId: widget.workId,
        imageFiles: preparedFiles,
      );

      if (result['success'] == true) {
        setState(() {
          _isUploading = false;
          _uploadSuccess = true;
          _files.clear();
        });
        return true;
      } else {
        setState(() {
          _isUploading = false;
          _errorMessage = result['message'] ?? 'Upload failed';
        });
        return false;
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
      return false;
    }
  }

  void _showMaxFilesReachedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Max Files Reached'),
        content: Text('You can only upload up to ${widget.maxFiles} files.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showUnsupportedFileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unsupported File Type'),
        content: Text('Please select a JPG, JPEG, or PNG image.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // Method to select image source (camera or gallery)
  Future<void> _showImageSourceDialog() async {
    if (_files.length >= widget.maxFiles) {
      _showMaxFilesReachedDialog();
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Image Source'),
          content: SingleChildScrollView(
            child: ListBody(
              children: [
                ListTile(
                  leading: Icon(Icons.photo_library),
                  title: Text('Gallery'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.camera_alt),
                  title: Text('Camera'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Public method to get the files to upload - called by the parent form
  Future<List<Map<String, dynamic>>> getFilesToUpload() async {
    if (_files.isEmpty) {
      return [];
    }

    final List<Map<String, dynamic>> preparedFiles = [];

    for (var fileItem in _files) {
      final fileData = await FormApiService.prepareImageFileForUpload(
        fileItem.file,
        customFileName: fileItem.name,
      );

      if (fileData != null) {
        preparedFiles.add(fileData);
      }
    }

    return preparedFiles;
  }

  // Method to mark files as uploaded
  void markFilesAsUploaded() {
    setState(() {
      _uploadSuccess = true;
      _files.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_upload, color: Colors.blue[700]),
              SizedBox(width: 10),
              Text(
                'Upload Documents',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Upload up to ${widget.maxFiles} files (images or PDFs)',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          SizedBox(height: 16),

          // Show files
          if (_files.isNotEmpty) ...[
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected Files:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  ...List.generate(
                    _files.length,
                    (index) => ListTile(
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      leading: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _files[index].type.contains('image')
                              ? Colors.blue[100]
                              : Colors.red[100],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _files[index].type.contains('image')
                              ? Icons.image
                              : Icons.picture_as_pdf,
                          color: _files[index].type.contains('image')
                              ? Colors.blue[700]
                              : Colors.red[700],
                        ),
                      ),
                      title: Text(
                        _files[index].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(_files[index].type),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _files.removeAt(index);
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
          ],

          // Upload buttons
          if (_files.length < widget.maxFiles) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.image),
                    label: Text('Add Image'),
                    onPressed: widget.enabled ? _showImageSourceDialog : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.picture_as_pdf),
                    label: Text('Add File'),
                    onPressed: widget.enabled ? _pickFile : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          SizedBox(height: 10),
          if (_isUploading)
            Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text("Uploading files..."),
                ],
              ),
            )
          else if (_uploadSuccess)
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 10),
                  Text(
                    'Files uploaded successfully!',
                    style: TextStyle(color: Colors.green),
                  ),
                ],
              ),
            )
          else if (_errorMessage.isNotEmpty)
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage,
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class FileUploadItem {
  final File file;
  final String name;
  final String type;

  FileUploadItem({
    required this.file,
    required this.name,
    required this.type,
  });
}
