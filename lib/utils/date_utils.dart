import 'package:intl/intl.dart';

class Date_Utils {
  static final DateFormat dateFormat = DateFormat('dd-MM-yyyy');
  static final DateFormat timeFormat = DateFormat('hh:mm a');

  static String formatDate(DateTime date) {
    return dateFormat.format(date);
  }

  static DateTime parseDate(String dateStr) {
    return dateFormat.parse(dateStr); // Parses 'dd-MM-yyyy' formatted string
  }

  static DateTime parseTime(String timeStr) {
    return timeFormat.parse(timeStr); // Parses 'hh:mm a' formatted string
  }
}
