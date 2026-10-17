import 'package:intl/intl.dart';

class Date_Utils {
  static final DateFormat dateFormat = DateFormat('dd-MM-yyyy');
  static final DateFormat timeFormat = DateFormat('hh:mm a');

  static final RegExp _timePattern =
      RegExp(r'^(\d{1,2}):(\d{2})(?::([0-5]\d))?\s*([AaPp][Mm])?$');

  static String formatDate(DateTime date) {
    return dateFormat.format(date);
  }

  static DateTime parseDate(String dateStr) {
    return dateFormat.parse(dateStr); // Parses 'dd-MM-yyyy' formatted string
  }

  static DateTime parseTime(String timeStr) {
    return timeFormat.parse(timeStr); // Parses 'hh:mm a' formatted string
  }

  /// Strict 'dd-MM-yyyy' parse. Returns null instead of rolling invalid
  /// values over (e.g. '32-01-2025' or '2025-12-12') into a different date.
  static DateTime? tryParseDateStrict(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    try {
      return dateFormat.parseStrict(dateStr.trim());
    } catch (_) {
      return null;
    }
  }

  /// Parses '14:30', '02:30 PM', '2:30 pm', '02:30PM' or with seconds
  /// ('14:30:00', as Excel CSVs often store it; seconds are ignored).
  /// Returns a DateTime on 2000-01-01 (only hour/minute are meaningful),
  /// or null when the string is not a valid time.
  static DateTime? tryParseTimeFlexible(String? timeStr) {
    if (timeStr == null) return null;
    final match = _timePattern.firstMatch(timeStr.trim());
    if (match == null) return null;

    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(4)?.toUpperCase();

    if (minute > 59) return null;
    if (period == null) {
      if (hour > 23) return null;
    } else {
      if (hour < 1 || hour > 12) return null;
      if (period == 'PM' && hour != 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;
    }
    return DateTime(2000, 1, 1, hour, minute);
  }
}
