import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../repositories/patient_appointments_repository.dart';
import '../../../res/color.dart';
import '../../../res/components/buildDialogButton.dart';
import '../../../utils/date_utils.dart';

// Show this dialog when appointment is 10 days or less away
//
// [context] is the home screen's context. [repository] performs the "YES"
// confirmation update. [isMounted] reports whether the
// home screen is still mounted. [onCancelAppointment] runs the cancel flow
// ("NO"); [onShowAvailableDates] shows the available-dates dialog
// ("NOT SURE").
void showAppointmentReminderDialog({
  required BuildContext context,
  required String operationType,
  required String hospitalName,
  required DateTime appointmentDate,
  required String appointmentId,
  required PatientAppointmentsRepository repository,
  required User? Function() currentUser,
  required bool Function() isMounted,
  required Future<void> Function() onCancelAppointment,
  required VoidCallback onShowAvailableDates,
}) {
  if (kDebugMode) {
    print('=== SHOWING REMINDER DIALOG ===');
    print('Operation Type: $operationType');
    print('Hospital: $hospitalName');
    print('Appointment Date: $appointmentDate');
    print('Appointment ID: $appointmentId');
  }

  // Close any existing dialogs first to ensure reminder dialog can show
  try {
    Navigator.of(context, rootNavigator: true).popUntil((route) {
      if (kDebugMode) {
        print('Checking route: ${route.settings.name ?? route.toString()}');
      }
      return route.isFirst;
    });
  } catch (e) {
    if (kDebugMode) {
      print('Note: Could not close existing dialogs (may not be any): $e');
    }
  }

  String formattedDate = Date_Utils.formatDate(appointmentDate);

  if (kDebugMode) {
    print('Formatted Date: $formattedDate');
    print('About to call showDialog...');
  }

  showDialog(
    context: context,
    barrierDismissible: false, // Prevent dismissing by tapping outside
    // dialogContext closes the dialog; [context] (the screen) shows snackbars
    builder: (dialogContext) => AlertDialog(
      title: const Text('Appointment Reminder'),
      content: Text(
        'You have an appointment for $operationType with $hospitalName on $formattedDate. '
        'Do you still require this appointment?',
        style: const TextStyle(color: AppColors.blackColor),
      ),
      actions: <Widget>[
        buildDialogButton('YES', () async {
          // User confirms they still need the appointment
          // Close the reminder dialog first
          Navigator.of(dialogContext).pop();

          // Update appointment status to confirmed (if needed)
          try {
            final user = currentUser();
            if (user != null && appointmentId.isNotEmpty) {
              await repository.confirmAppointmentFromReminder(appointmentId);

              if (kDebugMode) {
                print('Appointment confirmed: $appointmentId');
              }

              // Show success message
              if (isMounted()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Appointment confirmed!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error confirming appointment: $e');
            }
            if (isMounted()) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error confirming appointment: $e'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }),
        SizedBox(
          height: 5,
        ),
        buildDialogButton('NO', () async {
          // User wants to cancel the appointment
          Navigator.of(dialogContext).pop(); // Close reminder dialog first
          await onCancelAppointment();
        }),
        SizedBox(
          height: 5,
        ),
        buildDialogButton('NOT SURE', () {
          // User is not sure - show available dates for rescheduling
          Navigator.of(dialogContext).pop(); // Close reminder dialog first
          // Show available dates after a short delay to ensure dialog is closed
          Future.delayed(const Duration(milliseconds: 300), () {
            if (isMounted()) {
              onShowAvailableDates();
            }
          });
        }),
      ],
    ),
  );

  if (kDebugMode) {
    print('✓ showDialog() called successfully');
  }
}
