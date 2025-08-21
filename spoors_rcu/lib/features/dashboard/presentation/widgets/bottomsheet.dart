import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:lottie/lottie.dart';
import '../../../../core/network/LocalJsonStorage.dart'; // Add this import

class FormListBottomSheet extends StatelessWidget {
  final Function(String)? onRecordTypeSelected;

  const FormListBottomSheet({
    Key? key,
    this.onRecordTypeSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7, // Limit max height
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Select Record Type',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),

          // FutureBuilder to load record types from Hive
          Flexible(
            // Make this flexible to avoid overflow
            child: FutureBuilder<List<String>>(
              future: _loadRecordTypes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: Lottie.asset(
                            'assets/animations/Loading1.json',
                            repeat: true,
                            animate: true,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Loading record types...',
                          style: TextStyle(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey[700],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    snapshot.data!.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'No record types available',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics:
                      const ClampingScrollPhysics(), // Better scroll behavior
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final recordType = snapshot.data![index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: 0.5,
                      child: ListTile(
                        title: Text(
                          recordType,
                          // Handle text overflow
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2, // Allow up to 2 lines
                          style: TextStyle(fontSize: 15),
                        ),
                        dense: true, // Makes the ListTile more compact
                        onTap: () {
                          if (onRecordTypeSelected != null) {
                            onRecordTypeSelected!(recordType);
                          }
                        },
                        trailing: Icon(Icons.arrow_forward_ios, size: 16),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Method to load record types from JSON files first, then Hive as fallback
  Future<List<String>> _loadRecordTypes() async {
    try {
      // First try to load from records.json
      final recordsJsonData = await LocalJsonStorage.readResponse('records');
      if (recordsJsonData != null && recordsJsonData['record_types'] is List) {
        return List<String>.from(
            recordsJsonData['record_types'].map((e) => e.toString()));
      }

      // If not found, try loading from all_records.json
      final allRecordsJsonData =
          await LocalJsonStorage.readResponse('all_records');
      if (allRecordsJsonData != null && allRecordsJsonData['records'] is List) {
        // Extract unique record types
        final Set<String> uniqueTypes = {};
        for (var record in allRecordsJsonData['records']) {
          if (record is Map &&
              record['RecordTypeName'] != null &&
              record['RecordTypeName'] is String) {
            uniqueTypes.add(record['RecordTypeName']);
          }
        }
        return uniqueTypes.toList();
      }

      // Fall back to Hive if JSON files aren't available
      final box = await Hive.openBox('records');
      final recordTypes = box.get('record_types');

      if (recordTypes != null && recordTypes is List) {
        return List<String>.from(recordTypes.map((e) => e.toString()));
      }

      // If record_types is not available, try to extract from all_records in Hive
      final allRecords = box.get('all_records');
      if (allRecords != null &&
          allRecords is Map &&
          allRecords['records'] is List) {
        // Extract unique record types
        final Set<String> uniqueTypes = {};
        for (var record in allRecords['records']) {
          if (record is Map &&
              record['RecordTypeName'] != null &&
              record['RecordTypeName'] is String) {
            uniqueTypes.add(record['RecordTypeName']);
          }
        }
        return uniqueTypes.toList();
      }

      // Fallback to hardcoded list if nothing else works
      return [
        'Live Disbursement',
        'Cross Audit',
        'Individual Audit',
      ];
    } catch (e) {
      return []; // Return empty list on error
    }
  }
}
