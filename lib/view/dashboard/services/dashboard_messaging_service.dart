import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/appointment_data.dart';
import '../../../notification/notification_services.dart';
import '../../../notification/push_notification_services.dart';
import '../../../repositories/dashboard_repository.dart';
import 'phone_formatting.dart';

/// Quick-action SMS templates, appointment reminders (SMS + push) and the
/// matching activity-log entries for the dashboard.
///
/// UI feedback (snackbars) is shown on the [BuildContext] passed in, guarded by
/// the caller's `isMounted` callback (the dashboard State's `mounted`).
class DashboardMessagingService {
  final DashboardRepository _repository;
  final PushNotificationServices _pushNotificationServices =
      PushNotificationServices();
  final NotificationServices _notificationServices = NotificationServices();

  DashboardMessagingService(this._repository);

  /// Send SMS for quick action template
  Future<void> sendQuickActionSMS(
    BuildContext context,
    bool Function() isMounted,
    AppointmentData appointment,
    String actionType,
  ) async {
    try {
      // Format phone number to E.164 format
      final cleanedPhone = formatPhoneToE164(appointment.phone);
      print('Quick Action: Original phone: ${appointment.phone}, Formatted: $cleanedPhone');

      // Get template message based on action type
      String templateName;
      String message;

      switch (actionType) {
        case 'offer_early_slot':
          templateName = 'Offer Early Slot';
          // Get current time for the offer
          final now = DateTime.now();
          final offerTime = DateFormat('hh:mm a').format(now.add(const Duration(hours: 1)));
          message = 'Good news! We have an earlier slot today at $offerTime. Reply 1 to claim.';
          break;
        case 'confirm_attendance':
          templateName = 'Confirm Attendance';
          message = 'Please confirm your ${appointment.formattedTime} appointment by replying 1.';
          break;
        case 'late_warning':
          templateName = 'Late Warning';
          message = 'Hi, we noticed you\'re a bit late. Are you still coming?';
          break;
        default:
          return;
      }

      // Show loading indicator
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sending $templateName...'),
            duration: const Duration(seconds: 1),
          ),
        );
      }

      // Send SMS via Cloud Function (sendCustomSms only). There is no
      // fallback to sendSmsReminder: that would send the standard reminder
      // text instead of this template and change the appointment status.
      bool smsSent = false;
      String errorMessage = '';

      try {
        final result = await _repository.sendCustomSms(
          phone: cleanedPhone,
          message: message,
        );

        if (result.data != null && result.data['success'] == true) {
          smsSent = true;
          print('Custom SMS sent successfully via sendCustomSms');
        } else if (result.data != null) {
          errorMessage = (result.data['message'] ??
                  result.data['error'] ??
                  'SMS sending failed')
              .toString();
          print('sendCustomSms failed: $errorMessage');
        } else {
          errorMessage = 'No response from sendCustomSms';
        }
      } catch (e) {
        errorMessage = 'SMS service error: ${e.toString()}';
        print('sendCustomSms error: $e');
      }

      // Log to activity log (only when the SMS actually went out)
      if (smsSent) {
        await logManualAdminAction(
          appointment.name,
          templateName,
          message,
        );
      }

      // Show success/error message
      if (isMounted()) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        
        // Check if error is about landline
        bool isLandlineError = errorMessage.toLowerCase().contains('landline');
        String displayMessage;
        
        if (smsSent) {
          displayMessage = 'Manual $templateName sent to ${appointment.name}.';
        } else if (isLandlineError) {
          displayMessage = 'Cannot send SMS: ${appointment.phone} appears to be a landline number. SMS can only be sent to mobile numbers.';
        } else {
          displayMessage = 'Failed to send $templateName to ${appointment.name}.${errorMessage.isNotEmpty ? '\nError: ${errorMessage.length > 80 ? errorMessage.substring(0, 80) + "..." : errorMessage}' : ''}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayMessage),
            backgroundColor: smsSent ? Colors.green : Colors.red,
            duration: Duration(seconds: smsSent ? 3 : (isLandlineError ? 6 : 5)),
            action: isLandlineError ? SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ) : null,
          ),
        );
      }
    } catch (e) {
      if (isMounted()) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending SMS: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      print('Error in _sendQuickActionSMS: $e');
    }
  }

  /// Log manual admin action to activity log
  Future<void> logManualAdminAction(
    String patientName,
    String templateName,
    String message,
  ) async {
    try {
      final now = DateTime.now();
      final timeStr = DateFormat('hh:mm a').format(now);

      await _repository.addActivityLogEntry(
        message: '$timeStr: Manual Admin Action - $templateName sent to $patientName',
        type: 'maintenance',
      );
    } catch (e) {
      print('Error logging manual admin action: $e');
    }
  }

  /// Send reminder via notification and SMS
  Future<void> triggerReminder(
      BuildContext context,
      bool Function() isMounted,
      String patientId,
      String phone,
      String patientName,
      String appointmentDate,
      String appointmentTime) async {
    try {
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sending reminder...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Format phone number to E.164 format for SMS
      final cleanedPhone = formatPhoneToE164(phone);
      print('Reminder: Original phone: $phone, Formatted: $cleanedPhone');

      // Get current appointment status from Firestore
      String currentStatus = 'active';
      try {
        final appointmentSnapshot = await _repository
            .getAppointmentByPatientAndDate(patientId, appointmentDate);

        if (appointmentSnapshot.docs.isNotEmpty) {
          currentStatus =
              appointmentSnapshot.docs.first.data()['status'] ?? 'active';
        }
      } catch (e) {
        print('Error fetching appointment status: $e');
      }

      // Send SMS via Cloud Function
      bool smsSent = false;
      String smsMessage = '';
      try {
        final result = await _repository.sendSmsReminder(
          patientPhone: cleanedPhone,
          slotStatus: currentStatus,
          patientId: patientId,
          appointmentDate: appointmentDate,
          appointmentTime: appointmentTime,
        );

        if (result.data != null && result.data['success'] == true) {
          smsSent = true;
          smsMessage = result.data['message'] ?? 'SMS sent successfully';
        } else {
          smsMessage = result.data?['message'] ?? 'SMS sending failed';
        }
      } catch (e) {
        print('Error calling Cloud Function for SMS: $e');
        smsMessage = 'SMS service unavailable: ${e.toString()}';
      }

      // Get device token for push notification
      String? deviceToken =
          await _notificationServices.getDeviceToken(patientId);

      bool notificationSent = false;
      if (deviceToken != null) {
        notificationSent =
            await _pushNotificationServices.sendNotificationToUser(
          deviceToken: deviceToken,
          title: 'Appointment Reminder',
          body:
              'You have an appointment on $appointmentDate at $appointmentTime. Please confirm your attendance.',
          data: {
            'type': 'appointment_reminder',
            'patientId': patientId,
            'date': appointmentDate,
            'time': appointmentTime,
            'action': 'reminder',
          },
          context: context,
        );
      }

      // Show appropriate success/error message
      if (isMounted()) {
        String message;
        Color backgroundColor;
        
        // Check if error is about landline
        bool isLandlineError = smsMessage.toLowerCase().contains('landline');

        if (smsSent && notificationSent) {
          message = 'Reminder sent successfully via SMS and push notification!';
          backgroundColor = Colors.green;
        } else if (smsSent && deviceToken == null) {
          message =
              'SMS sent successfully! (No device token for push notification)';
          backgroundColor = Colors.green;
        } else if (smsSent && !notificationSent) {
          message = 'SMS sent successfully! (Push notification failed)';
          backgroundColor = Colors.orange;
        } else if (!smsSent && notificationSent) {
          if (isLandlineError) {
            message = 'Push notification sent! (SMS failed: $phone appears to be a landline number)';
          } else {
            message = 'Push notification sent! (SMS failed: $smsMessage)';
          }
          backgroundColor = Colors.orange;
        } else {
          if (isLandlineError) {
            message = 'Cannot send SMS: $phone appears to be a landline number. SMS can only be sent to mobile numbers.';
          } else {
            message =
                'Reminder failed: SMS - $smsMessage, Push - ${deviceToken == null ? "No device token" : "Failed"}';
          }
          backgroundColor = Colors.red;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
            duration: Duration(seconds: isLandlineError ? 6 : 3),
            action: isLandlineError ? SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ) : null,
          ),
        );
      }
    } catch (e) {
      if (isMounted()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending reminder: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
