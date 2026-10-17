import 'dart:typed_data';

/// Non-web builds (Android/iOS) never show the dashboard; nothing to pick.
Future<Uint8List?> pickCsvFileWeb() async => null;
