import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../repositories/patient_appointments_repository.dart';

/// Startup reminder check for the patient home screen.
///
/// For the first active appointment 0-10 days away, calls [showReminder]
/// after 3000ms (if [isMounted]); for appointments 30+ days away calls
/// [sendUpcomingNotification].
Future<void> checkUpcomingAppointments({
  required User? user,
  required PatientAppointmentsRepository repository,
  required bool Function() isMounted,
  required void Function(String operationType, String hospitalName,
          DateTime appointmentDate, String appointmentId)
      showReminder,
  required void Function(String patientName, String operationType,
          String hospitalName, DateTime appointmentDate)
      sendUpcomingNotification,
}) async {
  if (user == null || user.email == null) {
    if (kDebugMode) {
      print('User not logged in, skipping appointment check');
    }
    return;
  }

  String? userEmail = user.email;

  if (kDebugMode) {
    print('=== REMINDER CHECK STARTED ===');
    print('User ID: ${user.uid}');
    print('User Email: $userEmail');
  }

  // SECURITY: Query active appointments for the user - filter by patientID
  QuerySnapshot snapshot = await repository.getActiveAppointmentsForReminder(
    uid: user.uid,
    email: userEmail,
  );

  if (kDebugMode) {
    print('Total active appointments found: ${snapshot.docs.length}');
  }

  if (snapshot.docs.isEmpty) {
    if (kDebugMode) {
      print('No active appointments found - reminder check complete');
    }
    return;
  }

  DateTime now = DateTime.now();
  final DateFormat customDateFormat =
      DateFormat('dd-MM-yyyy'); // Define the custom date format

  for (var doc in snapshot.docs) {
    try {
      String appointmentId = doc.id; // Extract the document ID

      if (kDebugMode) {
        print('--- Processing appointment: $appointmentId ---');
        print('Appointment data: ${doc.data()}');
      }

      // Skip reminders for claimed slots (newly claimed appointments should not trigger reminders)
      // Safely check for fields that may not exist in the document
      Map<String, dynamic>? appointmentData = doc.data() as Map<String, dynamic>?;
      bool skipReminder = (appointmentData?['skipReminder'] == true) ||
                         (appointmentData?['isClaimedSlot'] == true);
      if (skipReminder) {
        if (kDebugMode) {
          print("Skipping reminder for claimed slot appointment: $appointmentId");
          print("skipReminder: ${appointmentData?['skipReminder']}, isClaimedSlot: ${appointmentData?['isClaimedSlot']}");
        }
        continue; // Skip this appointment
      }

      // Parse the date using the custom format (dd-MM-yyyy)
      String? dateString = appointmentData?['date']?.toString();
      if (dateString == null || dateString.isEmpty) {
        if (kDebugMode) {
          print("ERROR: Date field is null or empty for appointment: $appointmentId");
        }
        continue;
      }

      DateTime appointmentDate;
      try {
        appointmentDate = customDateFormat.parse(dateString);
      } catch (e) {
        if (kDebugMode) {
          print("ERROR: Failed to parse date '$dateString' for appointment: $appointmentId");
          print("Error: $e");
          print("Expected format: dd-MM-yyyy");
        }
        continue; // Skip this appointment if date parsing fails
      }

      String? hospitalId = appointmentData?['hospital']?.toString(); // Hospital ID (or name)
      String? operationType = appointmentData?['operationType']?.toString();

      if (kDebugMode) {
        print("Parsed appointment date: $appointmentDate");
        print("Hospital: $hospitalId, Operation: $operationType");
      }

      // Calculate days until appointment - normalize to date only (ignore time)
      DateTime appointmentDateOnly = DateTime(appointmentDate.year, appointmentDate.month, appointmentDate.day);
      DateTime nowDateOnly = DateTime(now.year, now.month, now.day);
      int daysUntilAppointment = appointmentDateOnly.difference(nowDateOnly).inDays;

      if (kDebugMode) {
        print("=== DATE CALCULATION DEBUG ===");
        print("Raw appointment date string: $dateString");
        print("Parsed appointment date: $appointmentDate");
        print("Current date/time (now): $now");
        print("Appointment Date Only: $appointmentDateOnly");
        print("Now Date Only: $nowDateOnly");
        print("Days until appointment: $daysUntilAppointment");
        print("Condition check: daysUntilAppointment <= 10 && daysUntilAppointment >= 0");
        print("Result: ${daysUntilAppointment <= 10 && daysUntilAppointment >= 0}");
      }

      // Show reminder dialog if appointment is 10 days or less away
      // This dialog should show every time the app opens
      if (daysUntilAppointment <= 10 && daysUntilAppointment >= 0) {
        if (kDebugMode) {
          print("✓✓✓ REMINDER TRIGGERED ✓✓✓");
          print("Appointment: ${appointmentData?['name'] ?? 'Unknown'}");
          print("Days until: $daysUntilAppointment");
          print("Scheduling dialog to show in 2500ms...");
        }
        // Show dialog for the first appointment that is within 10 days
        // Use a sufficient delay to ensure any other dialogs are closed first
        // Increased delay to 3000ms to ensure available dates dialog closes first
        Future.delayed(const Duration(milliseconds: 3000), () {
          if (isMounted()) {
            if (kDebugMode) {
              print(">>> NOW ATTEMPTING TO SHOW REMINDER DIALOG <<<");
              print("Context valid: ${isMounted()}");
            }
            // Check if context is still valid before showing dialog
            try {
              showReminder(
                operationType ?? 'Unknown Operation',
                hospitalId ?? 'Unknown Hospital',
                appointmentDate,
                appointmentId,
              );
              if (kDebugMode) {
                print("✓ Reminder dialog showDialog() called successfully");
              }
            } catch (e, stackTrace) {
              if (kDebugMode) {
                print("✗ ERROR showing reminder dialog: $e");
                print("Stack trace: $stackTrace");
              }
            }
          } else {
            if (kDebugMode) {
              print("✗ Widget not mounted, cannot show dialog");
            }
          }
        });
        break; // Show dialog for the first appointment within 10 days
      } else if (daysUntilAppointment > 10) {
        if (kDebugMode) {
          print("Appointment is ${daysUntilAppointment} days away (more than 10) - NO REMINDER");
        }
        // If appointment is more than 10 days away, send notification (30+ days)
        if (daysUntilAppointment >= 30) {
          if (kDebugMode) {
            print("Sending notification for appointment: ${appointmentData?['name'] ?? 'Unknown'} (${daysUntilAppointment} days away)");
          }
          sendUpcomingNotification(
            appointmentData?['name'] ?? 'Patient',
            operationType ?? 'Unknown Operation',
            hospitalId ?? 'Unknown Hospital',
            appointmentDate,
          );
        } else {
          if (kDebugMode) {
            print("Appointment is ${daysUntilAppointment} days away (more than 10, less than 30) - no reminder");
          }
        }
      } else {
        if (kDebugMode) {
          print("Appointment is in the past: $daysUntilAppointment days (negative = past date) - NO REMINDER");
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print("ERROR processing appointment ${doc.id}: $e");
        print("Stack trace: $stackTrace");
      }
      continue; // Continue with next appointment if this one fails
    }
  }

  if (kDebugMode) {
    print('=== REMINDER CHECK COMPLETE ===');
  }
}
