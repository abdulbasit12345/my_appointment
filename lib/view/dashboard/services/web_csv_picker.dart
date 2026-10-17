// dart:html only exists on the web. Importing it unconditionally broke the
// Android/iOS builds, since main.dart imports the dashboard on every platform.
export 'web_csv_picker_stub.dart'
    if (dart.library.html) 'web_csv_picker_web.dart';
