import 'package:flutter/material.dart';

import '../../../models/appointment_data.dart';
import '../../../utils/appointment_status.dart';

/// True when the reminder was sent and the patient has not replied yet
/// ('reminder_sent_awaiting_reply' in any case, or 'awaitingReply'),
/// matching the status badge.
bool _isAwaitingReply(AppointmentData appointment) =>
    AppointmentStatus.kindOf(appointment.status) ==
    AppointmentStatusKind.reminderSent;

/// True when nobody holds the slot any more (cancelled, or released as
/// 'AVAILABLE'/'available'), so there is no patient to message.
bool _isCancelledOrAvailable(AppointmentData appointment) =>
    AppointmentStatus.isCancelled(appointment.status) ||
    AppointmentStatus.kindOf(appointment.status) ==
        AppointmentStatusKind.available;

/// Get reminder button text based on appointment status
String reminderButtonText(AppointmentData appointment) {
  // Check if reminder was sent and awaiting reply (case-insensitive)
  final status = appointment.status.toLowerCase();
  if (_isAwaitingReply(appointment)) {
    return 'Reminder Sent';
  }

  // Check if user has responded (confirmed or cancelled)
  // If userResponse exists, it means user already responded to a previous reminder
  if (appointment.userResponse != null &&
      appointment.userResponse!.isNotEmpty) {
    return 'Send Reminder';
  }

  // Check if status is CONFIRMED (user confirmed after reminder)
  if (status == 'confirmed') {
    return 'Send Reminder';
  }

  // Default state - no reminder sent yet
  return 'Remind';
}

/// Get reminder button icon based on appointment status
IconData reminderButtonIcon(AppointmentData appointment) {
  if (_isAwaitingReply(appointment)) {
    return Icons.check_circle;
  }
  return Icons.send;
}

/// Get reminder button color based on appointment status
Color reminderButtonColor(AppointmentData appointment) {
  if (_isAwaitingReply(appointment)) {
    return Colors.green; // Green when reminder sent
  }
  return const Color(0xFF1976D2); // Blue for default/active state
}

/// Check if reminder button should be enabled
bool isReminderButtonEnabled(AppointmentData appointment) {
  // Disable if reminder was just sent (waiting for reply)
  // Button will be enabled again once user responds (status changes or userResponse is set)
  if (_isAwaitingReply(appointment)) {
    return false; // Disabled until user responds
  }
  // No patient to remind on a cancelled or released slot
  if (_isCancelledOrAvailable(appointment)) {
    return false;
  }
  return true; // Enabled for sending new reminder
}

/// Check if the quick SMS actions button should be enabled
bool isQuickActionsEnabled(AppointmentData appointment) =>
    !_isCancelledOrAvailable(appointment);
