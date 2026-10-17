// Web implementation of [pickCsvFileWeb]; selected by web_csv_picker.dart.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'dart:async';
import 'dart:typed_data';

/// Web-specific file picker using native HTML input (more reliable than file_picker on web)
Future<Uint8List?> pickCsvFileWeb() async {

  final completer = Completer<Uint8List?>();
  html.FileUploadInputElement? input;
  
  try {
    // Create a hidden file input element
    input = html.FileUploadInputElement()
      ..accept = '.csv'
      ..style.display = 'none';
    
    html.document.body?.append(input);

    // Set up a timeout to complete with null if user doesn't select
    Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        input?.remove();
        completer.complete(null);
      }
    });

    // Listen for file selection
    input.onChange.listen((e) async {
      try {
        final files = input?.files;
        if (files == null || files.isEmpty) {
          input?.remove();
          if (!completer.isCompleted) {
            completer.complete(null);
          }
          return;
        }

        final file = files[0];
        print('📁 Selected file: ${file.name}, size: ${file.size} bytes');
        
        if (!file.name.toLowerCase().endsWith('.csv')) {
          print('❌ Invalid file type: ${file.name}');
          input?.remove();
          if (!completer.isCompleted) {
            completer.complete(null);
          }
          return;
        }

        // Read file as bytes
        final reader = html.FileReader();
        
        reader.onLoadEnd.listen((e) {
          input?.remove();
          try {
            if (reader.result != null) {
              final bytes = reader.result as Uint8List;
              print('✅ File read successfully: ${bytes.length} bytes');
              if (!completer.isCompleted) {
                completer.complete(bytes);
              }
            } else {
              print('❌ FileReader result is null');
              if (!completer.isCompleted) {
                completer.complete(null);
              }
            }
          } catch (e) {
            print('❌ Error processing file: $e');
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        });
        
        reader.onError.listen((e) {
          input?.remove();
          print('❌ File read error: $e');
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        });

        reader.readAsArrayBuffer(file);
      } catch (e) {
        input?.remove();
        print('❌ Error in file selection: $e');
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }
    });

    // Trigger file picker
    print('📂 Opening file picker...');
    input.click();
  } catch (e) {
    print('❌ Web file picker error: $e');
    input?.remove();
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }

  return completer.future;
}
