import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../../notification/notification_services.dart';
import '../../../notification/push_notification_services.dart';
import '../../../repositories/patient_appointments_repository.dart';
import '../../../utils/date_utils.dart';
import 'date_gap.dart';

/// Device-token and push-notification orchestration for the patient home
/// screen (reminder notification, cancel flow notifications, graph status).
///
/// Methods take `BuildContext Function() contextOf` instead of a context so
/// the screen's context is read at the same moment the original inline code
/// read it (after the awaits), keeping behaviour identical.
class PatientHomeNotificationService {
  final PatientAppointmentsRepository _repository;
  final NotificationServices _notificationServices;
  final PushNotificationServices _pushNotificationServices;

  PatientHomeNotificationService({
    required PatientAppointmentsRepository repository,
    required NotificationServices notificationServices,
    required PushNotificationServices pushNotificationServices,
  })  : _repository = repository,
        _notificationServices = notificationServices,
        _pushNotificationServices = pushNotificationServices;

  //this method is called inside the init state function
  Future<void> initializeNotifications(User? user) async {
    try {
      if (user == null) {
        if (kDebugMode) {
          print('User not logged in, cannot initialize notifications');
        }
        return;
      }

      // Note: setupInteractMessage is now called in main.dart at app startup
      // We only need to get the device token here for this specific user

      final String? token =
          await _notificationServices.getDeviceToken(user.uid);
      _notificationServices.isTokenRefresh(user.uid);

      if (kDebugMode) {
        if (token != null) {
          print('Device Token: $token');
        } else {
          print('Device Token: null (not available)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing notifications: $e');
      }
    }
  }

  //send notificaion to upcamming appointments
  Future<void> sendUpcomingAppointmentNotification({
    required User? user,
    required BuildContext Function() contextOf,
    required String patientName,
    required String operationType,
    required String hospitalName,
    required DateTime appointmentDate,
  }) async {
    try {
      // Use intl DateFormat to format the appointment date
      String formattedDate = DateFormat('dd-MM-yyyy').format(appointmentDate);

      if (user == null) {
        if (kDebugMode) {
          print('User not logged in, cannot send notification');
        }
        return;
      }

      String? deviceToken = await _notificationServices.getDeviceToken(user.uid);

      if (deviceToken == null) {
        if (kDebugMode) {
          print('Cannot send notification: Device token is null');
        }
        return;
      }

      final success = await _pushNotificationServices.sendNotificationToUser(
        deviceToken: deviceToken,
        title: '$patientName: You have an appointment for $operationType',
        body:
            'Your appointment is at $hospitalName on $formattedDate (in 4 weeks). This is a reminder for you.',
        data: {
          'type': 'appointment_reminder',
          'operationType': operationType,
          'hospital': hospitalName,
          'appointmentDate': formattedDate,
        },
        context: contextOf(),
      );

      if (kDebugMode) {
        print('Notification sent: $success');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending upcoming appointment notification: $e');
      }
    }
  }

  /// Cancels [documentId] after the ownership check has passed: notifies
  /// other patients (booked 60+ days out) with a cancellation push, sets the
  /// status to 'cancelled', schedules the legacy graph notifications and
  /// updates the AppointmentGraph status.
  ///
  /// Errors from the token lookup, the queries and the status update are not
  /// caught here; the caller's catch handles them (as before).
  Future<void> cancelAppointmentAndNotify({
    required User user,
    required String documentId,
    required DateTime appointmentDate,
    required String operationType,
    required String hospitalName,
    required BuildContext Function() contextOf,
  }) async {
    // Get current device token.
    final String? currentToken =
        await _notificationServices.getDeviceToken(user.uid);

    if (currentToken == null) {
      if (kDebugMode) {
        print('Warning: Current device token is null. Cannot filter current device from notifications.');
      }
    } else {
      if (kDebugMode) {
        print('Current device token: $currentToken');
      }
    }

    // Fetch all active appointments.
    final QuerySnapshot querySnapshot =
        await _repository.getAllBookedAppointments();

    DateTime currentDate = DateTime.now();
    final DateFormat customDateFormat =
        DateFormat('dd-MM-yyyy'); // Custom date format
    final List<String> deviceTokensToNotify = [];

    // Loop through each appointment.
    for (final doc in querySnapshot.docs) {
      // Web/CSV bookings have no app user (patientID null) and can't be
      // notified; skip them and any record with an unreadable date.
      final docData = doc.data() as Map<String, dynamic>;
      final docPatientId = docData['patientID'];
      final docDate = docData['date'];
      if (docPatientId is! String || docPatientId.isEmpty || docDate is! String) {
        continue;
      }
      DateTime docAppointmentDate;
      try {
        docAppointmentDate = customDateFormat.parse(docDate);
      } catch (_) {
        continue;
      }
      String userId = docPatientId;

      if (isDateGapSufficient(currentDate, docAppointmentDate)) {
        print(
            'Sufficient gap for user: $userId. Appointment date: $docAppointmentDate');

        // Fetch the token for the user.
        DocumentSnapshot tokenDoc = await _repository.getTokenData(userId);

        if (tokenDoc.exists) {
          Map<String, dynamic>? data =
              tokenDoc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('deviceToken')) {
            String deviceToken = data['deviceToken'].toString();
            if (kDebugMode) {
              print('Token for $userId: $deviceToken');
            }

            // Skip sending to the current device.
            if (currentToken != null && deviceToken != currentToken) {
              deviceTokensToNotify.add(deviceToken);
            } else if (currentToken == null) {
              // If current token is null, include all tokens
              deviceTokensToNotify.add(deviceToken);
            } else {
              if (kDebugMode) {
                print('Skipping token for current device.');
              }
            }
          } else {
            if (kDebugMode) {
              print('No deviceToken found for user: $userId');
            }
          }
        } else {
          if (kDebugMode) {
            print('Token document not found for user: $userId');
          }
        }
      }
    }

    if (kDebugMode) {
      print('Total tokens to notify: ${deviceTokensToNotify.length}');
    }

    // Send cancellation notifications.
    for (final token in deviceTokensToNotify) {
      try {
        final success = await _pushNotificationServices.sendNotificationToUser(
          deviceToken: token,
          title: 'Appointment Cancellation',
          body:
              'An appointment has been canceled. Check the graph for available slots.',
          data: {
            'type': 'appointment_cancellation',
            'operationType': operationType,
            'hospital': hospitalName,
            'appointmentDate': appointmentDate.toIso8601String(),
          },
          context: contextOf(),
        );
        if (kDebugMode) {
          if (success) {
            print('Notification sent to token: $token');
          } else {
            print('Failed to send notification to token: $token');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error sending notification to $token: $e');
        }
      }
    }

    // Update the appointment status to 'cancelled'.
    await _repository.markAppointmentCancelled(documentId);
    if (kDebugMode) {
      print('Appointment status updated to cancelled.');
    }

    // The freed slot is offered to patients booked after it by the
    // onAppointmentWritten Cloud Function (same path as SMS and dashboard
    // cancellations).

    // Send graph update notifications after cancellation (legacy support).
    Future.delayed(const Duration(milliseconds: 1000), () async {
      for (final token in deviceTokensToNotify) {
        try {
          await _sendGraphNotification(token, contextOf(), appointmentDate);
          if (kDebugMode) {
            print('Graph notification sent to $token');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error sending graph notification: $e');
          }
        }
      }
    });

    // Update the graph status.
    await _updateGraphStatus(user.uid, 'cancelled', appointmentDate);
    if (kDebugMode) {
      print('Graph status updated successfully.');
    }
  }

  //these methods are called inside cancelappointment methods
  Future<void> _sendGraphNotification(String deviceToken, BuildContext context,
      DateTime appointmentDate) async {
    try {
      String formattedDate = Date_Utils.formatDate(appointmentDate);

      if (kDebugMode) {
        print(
            'Sending graph notification to token: $deviceToken for date: $formattedDate'); // Debug log
      }

      final success = await _pushNotificationServices.sendNotificationToUser(
        deviceToken: deviceToken,
        title: 'Graph Updated: Slot Available',
        body:
            'A slot on $formattedDate has been canceled. Check the graph for availability.',
        data: {
          'type': 'view_graph',
          'appointmentDate': formattedDate,
        },
        context: context,
      );

      if (kDebugMode) {
        if (success) {
          print('Graph update notification sent successfully.');
        } else {
          print('Graph update notification failed to send.');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending graph notification: $e');
      }
    }
  }

  Future<void> _updateGraphStatus(
      String userId, String status, DateTime appointmentDate) async {
    try {
      String formattedDate = Date_Utils.formatDate(appointmentDate);
      String graphDocId =
          '$userId-$formattedDate-${appointmentDate.millisecondsSinceEpoch}';

      // Update the graph status to reflect the cancellation
      await _repository.updateAppointmentGraphStatus(graphDocId, status);

      if (kDebugMode) {
        print('Graph status updated successfully for document $graphDocId.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating graph status: $e');
      }
    }
  }
}
