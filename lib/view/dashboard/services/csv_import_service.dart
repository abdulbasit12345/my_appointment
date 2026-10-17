import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../repositories/dashboard_repository.dart';
import '../../../utils/date_utils.dart';
import '../widgets/import_summary_dialog.dart';
import 'phone_formatting.dart';
import 'web_csv_picker.dart';

/// CSV bulk import for the dashboard: pick file, parse, validate rows and
/// write them to Firestore (through [DashboardRepository]) in batches.
///
/// UI feedback (snackbars, summary dialog) is shown on the [BuildContext]
/// passed in, guarded by the caller's `isMounted` callback.
class CsvImportService {
  final DashboardRepository _repository;

  CsvImportService(this._repository);

  /// Import CSV file and bulk upload appointments
  /// 
  /// CSV FILE FORMAT REQUIREMENTS:
  /// - Required columns: Patient Name, Phone, Appt Date, Appt Time
  /// - Column names are case-insensitive and can have spaces
  /// Web-specific file picker using native HTML input (more reliable than file_picker on web)
  Future<Uint8List?> _pickFileWeb() async {
    if (!kIsWeb) return null;
    return pickCsvFileWeb();
  }

  /// Import CSV file from local storage
  /// - Date formats supported: "30 January 2026", "30-01-2026", "30/01/2026", "2026-01-30"
  /// - Time formats supported: "09:00 AM", "09:00", "21:00" (24-hour)
  /// - Phone numbers: Any format (quotes will be removed automatically)
  /// - Dates must be within the next 30 days from today to appear on dashboard
  /// - Status will be automatically set to 'active'
  Future<void> importCsvFile(
      BuildContext context, bool Function() isMounted) async {
    try {
      Uint8List? fileBytes;

      if (kIsWeb) {
        // Use native HTML file input for web (more reliable than file_picker on web)
        print('🌐 Web platform detected, using native file picker...');
        fileBytes = await _pickFileWeb();
        if (fileBytes == null) {
          print('❌ File picker returned null (user cancelled or error)');
          if (isMounted()) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('File selection cancelled or failed. Please try again.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        print('✅ File bytes received: ${fileBytes.length} bytes');
      } else {
        // Use file_picker for mobile/desktop
        FilePickerResult? result;
        try {
          result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['csv'],
            withData: true,
            allowMultiple: false,
          );
        } catch (pickerError, stackTrace) {
          print('❌ File picker error: $pickerError');
          print('Stack trace: $stackTrace');
          if (isMounted()) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error opening file picker: ${pickerError.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }

        if (result == null || result.files.isEmpty) {
          return;
        }

        final pickedFile = result.files.first;
        fileBytes = pickedFile.bytes;

        if (fileBytes == null) {
          if (isMounted()) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error: Could not read file. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      // Validate file bytes
      if (fileBytes.isEmpty) {
        if (isMounted()) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: Selected file is empty. Please select a valid CSV file with data.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Show loading indicator
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(width: 16),
                Text('Processing CSV file...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      if (fileBytes.isEmpty) {
        if (isMounted()) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: Selected file is empty. Please select a valid CSV file with data.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Convert bytes to string with proper encoding
      String fileContent;
      try {
        fileContent = String.fromCharCodes(fileBytes);
      } catch (e) {
        if (isMounted()) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: Could not read file content: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        print('❌ CSV Import Error: Failed to convert bytes to string: $e');
        return;
      }
      
      // Clean up the CSV content - remove problematic quotes and normalize
      String cleanedContent;
      try {
        cleanedContent = fileContent
            .replaceAll(RegExp(r"^'"), '') // Remove leading single quotes
            .replaceAll(RegExp(r"'$"), '') // Remove trailing single quotes
            .replaceAll(RegExp(r'^"'), '') // Remove leading double quotes
            .replaceAll(RegExp(r'"$'), ''); // Remove trailing double quotes
      } catch (e) {
        if (isMounted()) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing file content: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        print('❌ CSV Import Error: Failed to clean file content: $e');
        return;
      }
      
      // Parse CSV with proper quote handling
      List<List<dynamic>> csvData;
      try {
        csvData = const CsvToListConverter(
          shouldParseNumbers: false,
          fieldDelimiter: ',',
        ).convert(cleanedContent);
      } catch (e) {
        if (isMounted()) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error parsing CSV file: $e. Please ensure the file is a valid CSV format.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6),
            ),
          );
        }
        print('❌ CSV Import Error: Failed to parse CSV: $e');
        print('File content preview (first 500 chars): ${cleanedContent.length > 500 ? cleanedContent.substring(0, 500) : cleanedContent}');
        return;
      }

      if (csvData.isEmpty) {
        if (isMounted()) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: CSV file is empty'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Get header row (first row) and clean values thoroughly
      final headers = csvData[0]
          .map((e) {
            String value = e.toString();
            // Remove all types of quotes (single, double, smart quotes)
            value = value.replaceAll(RegExp(r"[''""]"), '');
            // Remove leading/trailing whitespace and normalize spaces
            value = value.trim().replaceAll(RegExp(r'\s+'), ' ');
            return value;
          })
          .toList();
      
      // Debug: Print headers for troubleshooting
      print('CSV Headers found: ${headers.map((h) => '"$h"').join(', ')}');
      
      // Find column indices (case-insensitive, with flexible matching)
      // Support both spaced and non-spaced column names
      int? nameIndex = _findColumnIndex(headers, ['patient name', 'name', 'patientname', 'patient', 'patient name']);
      int? phoneIndex = _findColumnIndex(headers, ['phone', 'phone number', 'phonenumber', 'mobile', 'contact']);
      int? dateIndex = _findColumnIndex(headers, ['appt date', 'appointment date', 'date', 'apptdate', 'appointmentdate', 'appt date']);
      int? timeIndex = _findColumnIndex(headers, ['appt time', 'appointment time', 'time', 'appttime', 'appointmenttime', 'appt time']);
      
      // Debug: Print found indices
      print('Column indices - Name: $nameIndex, Phone: $phoneIndex, Date: $dateIndex, Time: $timeIndex');

      // Check which columns are missing and provide helpful error message
      if (nameIndex == null || phoneIndex == null || dateIndex == null || timeIndex == null) {
        if (isMounted()) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          final missingColumns = <String>[];
          if (nameIndex == null) missingColumns.add('Patient Name');
          if (phoneIndex == null) missingColumns.add('Phone');
          if (dateIndex == null) missingColumns.add('Appt Date');
          if (timeIndex == null) missingColumns.add('Appt Time');
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error: Missing columns: ${missingColumns.join(', ')}. Found columns: ${headers.join(', ')}',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return;
      }

      // Process data rows (skip header and empty rows)
      final dataRows = csvData.skip(1).where((row) => row.isNotEmpty).toList();
      final validRows = <Map<String, String>>[];
      final List<String> errorLogs = [];
      final int totalRows = dataRows.length;

      for (int rowIndex = 0; rowIndex < dataRows.length; rowIndex++) {
        final row = dataRows[rowIndex];
        
        // Skip completely empty rows
        if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty)) {
          continue;
        }
        
        if (row.length <= nameIndex || row.length <= phoneIndex || 
            row.length <= dateIndex || row.length <= timeIndex) {
          errorLogs.add('Row ${rowIndex + 2}: Insufficient columns (found ${row.length}, need at least ${[nameIndex, phoneIndex, dateIndex, timeIndex].reduce((a, b) => a > b ? a : b) + 1})');
          continue;
        }

        // Clean and extract values, removing quotes
        String cleanValue(dynamic value) {
          if (value == null) return '';
          String cleaned = value.toString().trim();
          cleaned = cleaned.replaceAll(RegExp(r"^'"), '').replaceAll(RegExp(r"'$"), '');
          cleaned = cleaned.replaceAll(RegExp(r'^"'), '').replaceAll(RegExp(r'"$'), '');
          return cleaned.trim();
        }
        
        final name = cleanValue(row[nameIndex]);
        // For phone, convert scientific notation (Excel format like "9.27E+11")
        String phone = cleanValue(row[phoneIndex]);
        phone = convertScientificNotation(phone);
        final dateStr = cleanValue(row[dateIndex]);
        final timeStr = cleanValue(row[timeIndex]);

        // Check all required fields and skip if ANY is missing
        final missingFields = <String>[];
        if (name.isEmpty) missingFields.add('Patient Name');
        if (phone.isEmpty) missingFields.add('Phone');
        if (dateStr.isEmpty) missingFields.add('Appt Date');
        if (timeStr.isEmpty) missingFields.add('Appt Time');

        if (missingFields.isNotEmpty) {
          errorLogs.add('Row ${rowIndex + 2}: Missing ${missingFields.join(', ')}');
          continue;
        }

        // Validate date format
        try {
          _parseDate(dateStr);
        } catch (e) {
          errorLogs.add('Row ${rowIndex + 2}: Invalid date format - "$dateStr"');
          continue;
        }

        // Validate time format (should contain ':' or be in valid time format)
        if (!timeStr.contains(':') && 
            !timeStr.toUpperCase().contains('AM') && 
            !timeStr.toUpperCase().contains('PM')) {
          errorLogs.add('Row ${rowIndex + 2}: Invalid time format - "$timeStr"');
          continue;
        }

        validRows.add({
          'name': name,
          'phone': phone,
          'date': dateStr,
          'time': timeStr,
        });
      }

      if (validRows.isEmpty) {
        if (isMounted()) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No valid rows found. Skipped ${errorLogs.length} rows with missing data.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Check if exceeds 500 rows limit
      if (validRows.length > 500) {
        if (isMounted()) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: CSV contains more than 500 rows. Please split into smaller files.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Upload to Firestore using WriteBatch
      int successCount = 0;
      // Same for every row of this import; combined with the row number it
      // gives unique ids (successCount alone could repeat within a millisecond)
      final importId = DateTime.now().millisecondsSinceEpoch;

      // Process in batches of 500 (Firestore limit)
      for (int i = 0; i < validRows.length; i += 500) {
        final batch = _repository.newBatch();
        final batchRows = validRows.skip(i).take(500).toList();
        // Id of a document actually added to this batch (for verification)
        String? sampleDocId;

        for (int rowIndex = 0; rowIndex < batchRows.length; rowIndex++) {
          final row = batchRows[rowIndex];
          try {
            // Validate patientName and phoneNumber are not empty
            // Clean phone number - remove quotes and normalize
            String cleanPhone(String? phone) {
              if (phone == null) return '';
              String cleaned = phone.trim();
              cleaned = cleaned.replaceAll(RegExp(r"^'"), '').replaceAll(RegExp(r"'$"), '');
              cleaned = cleaned.replaceAll(RegExp(r'^"'), '').replaceAll(RegExp(r'"$'), '');
              // Convert scientific notation (Excel format like "9.27E+11") to regular number
              cleaned = convertScientificNotation(cleaned);
              return cleaned.trim();
            }
            
            final patientName = (row['name']?.toString() ?? '').trim();
            final rawPhoneNumber = cleanPhone(row['phone']?.toString());

            if (patientName.isEmpty || rawPhoneNumber.isEmpty) {
              errorLogs.add('Row ${i + rowIndex + 2}: Missing patient name or phone number');
              continue;
            }

            // Format phone number to E.164 format (Twilio-acceptable format with + sign)
            // This ensures the number is in the correct format for Twilio SMS sending
            final phoneNumber = formatPhoneToE164(rawPhoneNumber);
            
            // Log phone number formatting for debugging
            if (rawPhoneNumber != phoneNumber) {
              print('📞 Phone formatted: "$rawPhoneNumber" -> "$phoneNumber"');
            }
            
            // Validate that the formatted phone number has a + sign (E.164 format)
            // If formatting failed, try to add + prefix as fallback
            String finalPhoneNumber = phoneNumber;
            if (!phoneNumber.startsWith('+')) {
              // Try to add + prefix if it looks like a valid number
              if (phoneNumber.length >= 10 && phoneNumber.length <= 15) {
                finalPhoneNumber = '+' + phoneNumber;
                print('⚠️ Warning: Phone number "$rawPhoneNumber" was not formatted correctly. Added + prefix: "$finalPhoneNumber"');
              } else {
                errorLogs.add('Row ${i + rowIndex + 2}: Phone number "$rawPhoneNumber" could not be formatted to E.164 format (invalid format)');
                print('⚠️ Warning: Phone number "$rawPhoneNumber" was not formatted correctly. Result: "$phoneNumber"');
                // Continue anyway - the number might still work, but log the warning
                finalPhoneNumber = phoneNumber; // Use original formatted value
              }
            }

            // Parse and format date
            DateTime? parsedDate;
            try {
              // Try to parse date in various formats
              final originalDateStr = row['date']!;
              parsedDate = _parseDate(originalDateStr);
              
              // Validate parsed date - ensure year is reasonable (2000-2100)
              if (parsedDate.year < 2000 || parsedDate.year > 2100) {
                errorLogs.add('Row ${i + rowIndex + 2}: Invalid year in date - "$originalDateStr" (parsed as year ${parsedDate.year})');
                print('❌ Invalid year: $originalDateStr -> ${parsedDate.year}');
                continue;
              }
              
              // Additional validation: Check if date seems reasonable (not too far in future/past)
              final now = DateTime.now();
              final daysDifference = parsedDate.difference(now).inDays;
              if (daysDifference < -365 || daysDifference > 365) {
                print('⚠️ Warning: Date "$originalDateStr" is ${daysDifference.abs()} days ${daysDifference < 0 ? "in the past" : "in the future"}');
              }
              
            } catch (e) {
              errorLogs.add('Row ${i + rowIndex + 2}: Invalid date format - "${row['date']}" (Error: $e)');
              print('❌ Date parsing error for "${row['date']}": $e');
              continue;
            }

            // Format date as 'dd-MM-yyyy' - CRITICAL: Must be this format
            final formattedDate = Date_Utils.formatDate(parsedDate);
            
            // CRITICAL VALIDATION: Ensure the formatted date matches what we expect
            // If parsedDate is Jan 3, 2026, formattedDate should be "03-01-2026"
            // If we see "03-07-2031", something went wrong in parsing
            final expectedMonth = parsedDate.month;
            final expectedYear = parsedDate.year;
            final formattedParts = formattedDate.split('-');
            if (formattedParts.length == 3) {
              final formattedMonth = int.tryParse(formattedParts[1]);
              final formattedYear = int.tryParse(formattedParts[2]);
              if (formattedMonth != expectedMonth || formattedYear != expectedYear) {
                errorLogs.add('Row ${i + rowIndex + 2}: Date parsing mismatch - parsed as ${parsedDate.day}/${parsedDate.month}/${parsedDate.year} but formatted as "$formattedDate"');
                print('❌ Date mismatch: Parsed ${parsedDate.day}/${parsedDate.month}/${parsedDate.year} but formatted as "$formattedDate"');
                continue;
              }
            }
            
            // Validate formatted date format and year
            if (!formattedDate.contains('-') || formattedDate.split('-').length != 3) {
              errorLogs.add('Row ${i + rowIndex + 2}: Date formatting error - got "$formattedDate"');
              continue;
            }
            
            // Verify the formatted date has correct year (not 2031, 0026, etc.)
            final dateParts = formattedDate.split('-');
            if (dateParts.length == 3) {
              final year = int.tryParse(dateParts[2]);
              if (year == null || year < 2000 || year > 2100) {
                errorLogs.add('Row ${i + rowIndex + 2}: Invalid year in formatted date - "$formattedDate"');
                print('❌ Invalid formatted date year: $formattedDate');
                continue;
              }
            }
            
            print('✅ Date validated: "$formattedDate" (parsed from "${row['date']}")');

            // Format time - ensure it's in 'HH:mm' or 'hh:mm a' format
            String formattedTime = row['time']!.trim();
            // If time doesn't have AM/PM, assume 24-hour format
            if (!formattedTime.toUpperCase().contains('AM') && 
                !formattedTime.toUpperCase().contains('PM')) {
              // Already in 24-hour format, use as is
              if (!formattedTime.contains(':')) {
                errorLogs.add('Row ${i + rowIndex + 2}: Invalid time format - ${row['time']}');
                continue;
              }
            }

            // Generate unique document ID
            final docId = 'csv-$importId-${i + rowIndex}';

            // Create appointment document (reference is built by the repository)
            
            // Debug: Print appointment data before saving
            print('Saving appointment: $patientName, Date: $formattedDate, Time: $formattedTime, Status: active');
            print('Parsed date: $parsedDate, Formatted date: $formattedDate');
            print('Phone: "$rawPhoneNumber" -> "$finalPhoneNumber" (E.164 format)');
            
            // Ensure all required fields are set correctly
            // CRITICAL: status field MUST be present and exactly 'active' (lowercase)
            final appointmentData = <String, dynamic>{
              'patientID': 'csv-import-$importId-${i + rowIndex}',
              'name': patientName,
              'phone': finalPhoneNumber, // Use finalPhoneNumber (with + prefix if needed)
              'date': formattedDate, // Must be in 'dd-MM-yyyy' format (e.g., "10-01-2026")
              'time': formattedTime, // Can be 'HH:mm' or 'hh:mm a' format
              'status': 'active', // CRITICAL: Must be lowercase 'active' to match dashboard query
              'isPriority': false,
              'reallocationStatus': 'Original',
              'createdAt': FieldValue.serverTimestamp(),
              'email': '', // Empty email for CSV imports
              'address': '', // Empty address for CSV imports
              'hospital': '', // Empty hospital for CSV imports
              'userResponse': null, // No response yet
            };
            
            // Validate critical fields before saving
            if (appointmentData['status'] != 'active') {
              errorLogs.add('Row ${i + rowIndex + 2}: Status validation failed - ${appointmentData['status']}');
              continue;
            }
            
            if (!formattedDate.contains('-') || formattedDate.split('-')[2].length != 4) {
              errorLogs.add('Row ${i + rowIndex + 2}: Date format validation failed - $formattedDate');
              continue;
            }
            
            print('✅ Saving appointment: $patientName');
            print('   Date: $formattedDate (parsed from: ${row['date']})');
            print('   Time: $formattedTime');
            print('   Status: ${appointmentData['status']}');
            print('   Full data: $appointmentData');
            
            // Use set with merge: false to ensure all fields are set
            _repository.setAppointmentInBatch(batch, docId, appointmentData);
            sampleDocId = docId;
            
            print('Appointment document created with ID: $docId');

            // Only increment successCount if both name and phone are not empty
            if (patientName.isNotEmpty && finalPhoneNumber.isNotEmpty) {
              successCount++;
            }
          } catch (e) {
            errorLogs.add('Row ${i + rowIndex + 2}: Processing error - $e');
            print('Error processing row: $e');
          }
        }

        // Commit batch
        try {
          await _repository.commitBatch(batch);
          print('✅ Batch committed successfully');
          
          // Verify a sample document was saved correctly
          if (sampleDocId != null) {
            final verifyDoc = await _repository.getAppointmentDoc(sampleDocId);
            if (verifyDoc.exists) {
              final data = verifyDoc.data();
              print('✅ Verification - Sample document exists');
              print('   Status field: ${data?['status']}');
              print('   Date field: ${data?['date']}');
              if (data?['status'] != 'active') {
                print('⚠️ WARNING: Status field is missing or incorrect!');
              }
              final dateValue = data?['date'];
              if (dateValue == null || !(dateValue is String) || !dateValue.contains('-')) {
                print('⚠️ WARNING: Date field format is incorrect!');
              }
            }
          }
        } catch (e) {
          print('❌ Batch commit error: $e');
          if (isMounted()) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error uploading batch: $e'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      }

      // Show success dialog after batch commit
      if (isMounted()) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await showImportSummaryDialog(context, totalRows, successCount, errorLogs);
      }
    } catch (e, stackTrace) {
      // Log full error details for debugging
      print('❌ CSV Import Error: $e');
      print('Stack trace: $stackTrace');
      
      if (isMounted()) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // Provide user-friendly error message
        String errorMessage = 'Error importing CSV';
        if (e.toString().contains('LateInitializationError')) {
          errorMessage = 'Error: File picker initialization failed. Please try again or use a different browser.';
        } else if (e.toString().contains('has not been initialized')) {
          errorMessage = 'Error: File reading failed. Please ensure the file is a valid CSV and try again.';
        } else {
          errorMessage = 'Error importing CSV: ${e.toString()}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                // Show detailed error in console (for debugging)
                print('Full error details: $e\n$stackTrace');
              },
            ),
          ),
        );
      }
    }
  }

  /// Find column index by name (case-insensitive, flexible matching)
  int? _findColumnIndex(List<String> headers, List<String> possibleNames) {
    // Normalize a string for comparison
    String normalize(String str) {
      return str
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r"[''""]"), '') // Remove all quote types
          .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
          .trim();
    }
    
    for (var name in possibleNames) {
      final normalizedName = normalize(name);
      for (int i = 0; i < headers.length; i++) {
        final normalizedHeader = normalize(headers[i]);
        
        // Try exact match first
        if (normalizedHeader == normalizedName) {
          print('Matched "$name" to header "${headers[i]}" at index $i');
          return i;
        }
        // Try contains match (more flexible) - but only if both are substantial
        if (normalizedName.length >= 3 && normalizedHeader.length >= 3) {
          if (normalizedHeader.contains(normalizedName) || 
              normalizedName.contains(normalizedHeader)) {
            print('Matched "$name" to header "${headers[i]}" at index $i (contains match)');
            return i;
          }
        }
      }
    }
    print('Could not find column matching: ${possibleNames.join(', ')}');
    return null;
  }

  /// Parse date from various formats
  DateTime _parseDate(String dateStr) {
    // Clean the date string
    String cleanedDate = dateStr.trim();
    
    print('Parsing date: "$dateStr" (cleaned: "$cleanedDate")');
    
    // PRIORITY 1: Try formats with month names first (most reliable)
    // These formats are unambiguous and should be tried first
    final monthNameFormats = [
      'dd MMMM yyyy', // "10 January 2026" - FULL month name with spaces
      'd MMMM yyyy',  // "3 January 2026" (single digit day)
      'dd-MMMM-yyyy', // "10-January-2026" - FULL month name with dashes ⭐ NEW
      'd-MMMM-yyyy',  // "3-January-2026" (single digit day with dashes) ⭐ NEW
      'dd MMM yyyy',  // "10 Jan 2026" - SHORT month name with spaces
      'd MMM yyyy',   // "3 Jan 2026" (single digit day)
      'dd-MMM-yyyy',  // "10-Jan-2026" - SHORT month name with dashes ⭐ NEW
      'd-MMM-yyyy',   // "3-Jan-2026" (single digit day with dashes) ⭐ NEW
    ];
    
    for (var format in monthNameFormats) {
      try {
        final formatter = DateFormat(format, 'en_US'); // Use English locale for month names
        final parsed = formatter.parse(cleanedDate);
        
        // Validate year is reasonable
        if (parsed.year >= 2000 && parsed.year <= 2100) {
          print('✅ Parsed with format "$format": $parsed (${parsed.day}/${parsed.month}/${parsed.year})');
          return parsed;
        } else {
          print('⚠️ Parsed year ${parsed.year} is outside valid range (2000-2100)');
        }
      } catch (e) {
        // Continue to next format
        continue;
      }
    }
    
    // PRIORITY 2: Try unambiguous numeric formats (ISO format first)
    final numericFormats = [
      'yyyy-MM-dd',   // "2026-01-03" - ISO format (unambiguous)
      'yyyy/MM/dd',   // "2026/01/03" - ISO with slashes
      'dd-MM-yyyy',   // "03-01-2026" - DD-MM-YYYY (European format)
      'dd/MM/yyyy',   // "03/01/2026" - DD/MM/YYYY
    ];
    
    for (var format in numericFormats) {
      try {
        final formatter = DateFormat(format);
        final parsed = formatter.parse(cleanedDate);
        
        // Validate year is reasonable
        if (parsed.year >= 2000 && parsed.year <= 2100) {
          print('✅ Parsed with format "$format": $parsed (${parsed.day}/${parsed.month}/${parsed.year})');
          return parsed;
        }
      } catch (e) {
        continue;
      }
    }
    
    // PRIORITY 3: Try ambiguous US formats (MM-DD-YYYY) - LAST RESORT
    // These are ambiguous and should only be tried if nothing else works
    final ambiguousFormats = [
      'MM-dd-yyyy',   // "01-03-2026" - Could be Jan 3 or March 1
      'MM/dd/yyyy',   // "01/03/2026"
    ];
    
    for (var format in ambiguousFormats) {
      try {
        final formatter = DateFormat(format);
        final parsed = formatter.parse(cleanedDate);
        
        // Validate year is reasonable
        if (parsed.year >= 2000 && parsed.year <= 2100) {
          print('⚠️ Parsed with ambiguous format "$format": $parsed (${parsed.day}/${parsed.month}/${parsed.year})');
          return parsed;
        }
      } catch (e) {
        continue;
      }
    }

    // If all formats fail, try parsing as ISO string
    try {
      final parsed = DateTime.parse(cleanedDate);
      if (parsed.year >= 2000 && parsed.year <= 2100) {
        print('✅ Parsed as ISO string: $parsed');
        return parsed;
      }
    } catch (e) {
      // Continue to throw error
    }
    
    throw FormatException('Unable to parse date: $dateStr (cleaned: $cleanedDate). Please use formats like "03 January 2026" or "03-01-2026"');
  }
}
