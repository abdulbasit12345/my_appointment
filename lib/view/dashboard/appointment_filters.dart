import '../../models/appointment_data.dart';
import '../../utils/appointment_status.dart';
import '../../utils/date_utils.dart';

// Appointment list filters shared by the dashboard queue and the printed
// schedule, so both always show the same appointments.

/// Filter appointments to only include those within the next 30 days
/// Also includes cancelled appointments from the past 7 days to ensure they remain visible
List<AppointmentData> filterAppointmentsByDateRange(
    List<AppointmentData> appointments) {
  final now = DateTime.now();
  final startDate =
      DateTime(now.year, now.month, now.day); // Today at 00:00:00
  final endDate = startDate
      .add(const Duration(days: 30)); // 30 days from today (inclusive)

  // Include cancelled appointments from the past 7 days
  final cancelledStartDate = startDate.subtract(const Duration(days: 7));

  return appointments.where((appointment) {
    final appointmentDate = appointment.date;
    // Normalize appointment date to start of day for comparison
    final appointmentDateOnly = DateTime(
      appointmentDate.year,
      appointmentDate.month,
      appointmentDate.day,
    );

    // Check if appointment is cancelled (by status or userResponse)
    final isCancelled = AppointmentStatus.isCancelled(appointment.status) ||
        appointment.status == 'AVAILABLE' ||
        appointment.userResponse == 'Cancelled';

    // If cancelled, show if within past 7 days or future 30 days
    if (isCancelled) {
      return !appointmentDateOnly.isBefore(cancelledStartDate) &&
          !appointmentDateOnly.isAfter(endDate);
    }

    // For non-cancelled appointments, only show future appointments (today to 30 days)
    // IMPORTANT: Include today's appointments (use isBefore with startDate, not isAfter)
    return (appointmentDateOnly.isAtSameMomentAs(startDate) ||
            appointmentDateOnly.isAfter(startDate)) &&
        !appointmentDateOnly.isAfter(endDate);
  }).toList();
}

/// Apply search filter to appointments list
List<AppointmentData> applySearchFilter(
  List<AppointmentData> appointments,
  String category,
  String query,
) {
  if (query.isEmpty) {
    return appointments;
  }

  final lowerQuery = query.toLowerCase().trim();

  switch (category) {
    case 'Patient Name':
      return appointments.where((apt) {
        return apt.name.toLowerCase().contains(lowerQuery);
      }).toList();

    case 'Phone':
      return appointments.where((apt) {
        // Remove all non-digit characters for comparison
        final phoneDigits = apt.phone.replaceAll(RegExp(r'[^\d]'), '');
        final queryDigits = lowerQuery.replaceAll(RegExp(r'[^\d]'), '');
        // Match start, middle, or end of phone number
        return phoneDigits.contains(queryDigits) ||
            apt.phone.toLowerCase().contains(lowerQuery);
      }).toList();

    case 'Date':
      return appointments.where((apt) {
        // Match date as shown in table (e.g., "29 January 2026")
        final dateStr = apt.ukFormattedDate.toLowerCase();
        final dateStrShort = Date_Utils.formatDate(apt.date).toLowerCase();
        return dateStr.contains(lowerQuery) || dateStrShort.contains(lowerQuery);
      }).toList();

    default:
      return appointments;
  }
}
