import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_appointment/view/patient-views/dialog_screen.dart';

import '../../notification/notification_services.dart';
import '../../notification/push_notification_services.dart';
import '../../res/color.dart';
import '../../res/components/buildDialogButton.dart';
import '../../res/components/status_badge.dart';
import '../../utils/date_utils.dart';
import '../../services/appointment_service.dart';
import '../selection_view.dart';
import 'add-appoinment.dart';
import 'appointment_graph_screen.dart';

class PatientHomeViewNew extends StatefulWidget {
  const PatientHomeViewNew({super.key});

  @override
  State<PatientHomeViewNew> createState() => _PatientHomeViewNewState();
}

class _PatientHomeViewNewState extends State<PatientHomeViewNew> {
  final NotificationServices _notificationServices = NotificationServices();
  final PushNotificationServices _pushNotificationServices =
      PushNotificationServices();
  final AppointmentService _appointmentService = AppointmentService();
  
  // Use local user instead of global to ensure it's always current
  User? get currentUser => FirebaseAuth.instance.currentUser;
  
  //final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  // Removed _dialogShown flag - dialog should show every time app opens if appointment is within 10 days

  DialogScreen dialogScreen = DialogScreen();

  @override
  void initState() {
    super.initState();

    if (kDebugMode) {
      print('initState is running .......');
    }
    _initializeNotifications();
    
    // Use WidgetsBinding to ensure the context is ready before showing dialogs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Show available dates dialog first (if any available dates exist)
      // Then check for appointment reminders after a delay
      showAvailableDatesDialog();
      
      // Check for appointment reminders after ensuring UI is ready
      // This ensures the reminder dialog shows every time the app opens
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) {
          _checkUpcomingAppointments();
        }
      });
    });
  }

  //show available dialog box

  //send notificaion to upcamming appointments
  Future<void> _sendUpcomingAppointmentNotification(
      String patientName,
      String operationType,
      String hospitalName,
      DateTime appointmentDate) async {
    try {
      // Use intl DateFormat to format the appointment date
      String formattedDate = DateFormat('dd-MM-yyyy').format(appointmentDate);

      final user = currentUser;
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
        context: context,
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

  Future<void> _checkUpcomingAppointments() async {
    final user = currentUser;
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
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('Appointments')
        .where('patientID', isEqualTo: user.uid)
        .where('email', isEqualTo: userEmail)
        .where('status', isEqualTo: 'active')
        .get();

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
            if (mounted) {
              if (kDebugMode) {
                print(">>> NOW ATTEMPTING TO SHOW REMINDER DIALOG <<<");
                print("Context valid: ${context.mounted}");
              }
              // Check if context is still valid before showing dialog
              try {
                _showAppointmentConfirmationDialog(
                  context,
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
            _sendUpcomingAppointmentNotification(
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

// Show this dialog when appointment is 10 days or less away
  void _showAppointmentConfirmationDialog(
      BuildContext context,
      String operationType,
      String hospitalName,
      DateTime appointmentDate,
      String appointmentId) {
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
    
    //String formattedDate = _dateFormat.format(appointmentDate); // Use your date formatter
    String formattedDate = Date_Utils.formatDate(appointmentDate);

    if (kDebugMode) {
      print('Formatted Date: $formattedDate');
      print('About to call showDialog...');
    }

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => AlertDialog(
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
            Navigator.of(context).pop();
            
            // Update appointment status to confirmed (if needed)
            try {
              final user = currentUser;
              if (user != null && appointmentId.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('Appointments')
                    .doc(appointmentId)
                    .update({
                  'status': 'active',
                  'confirmed': true,
                  'reminderAcknowledged': true,
                  'lastUpdated': FieldValue.serverTimestamp(),
                });
                
                if (kDebugMode) {
                  print('Appointment confirmed: $appointmentId');
                }
                
                // Show success message
                if (mounted) {
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
              if (mounted) {
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
            Navigator.of(context).pop(); // Close reminder dialog first
            await _cancelAppointment(
                appointmentId, appointmentDate, operationType, hospitalName);
          }),
          SizedBox(
            height: 5,
          ),
          buildDialogButton('NOT SURE', () {
            // User is not sure - show available dates for rescheduling
            Navigator.of(context).pop(); // Close reminder dialog first
            // Show available dates after a short delay to ensure dialog is closed
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
            showAvailableDatesDialog();
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

  //this is used inside the scaffold for getting streem data
  // SECURITY: Filter by both email AND patientID to ensure patient-specific appointments
  Stream<QuerySnapshot> _getAppointments() {
    final user = currentUser;
    if (user == null || user.email == null) {
      // Return empty stream if user is not logged in
      // Create an empty QuerySnapshot by querying with impossible condition
      return FirebaseFirestore.instance
          .collection('Appointments')
          .where('patientID', isEqualTo: '__no_user__')
          .snapshots();
    }
    
    return FirebaseFirestore.instance
        .collection('Appointments')
        .where('patientID', isEqualTo: user.uid) // Primary filter by patientID
        .where('email', isEqualTo: user.email) // Secondary filter by email
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  //this method is called inside the init state function
  Future<void> _initializeNotifications() async {
    try {
      final user = currentUser;
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

  //these methods are called inside cancelappointment methods
  Future<void> _sendGraphNotification(String deviceToken, BuildContext context,
      DateTime appointmentDate) async {
    try {
      //String formattedDate = DateFormat('yyyy-MM-dd').format(appointmentDate);
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
      //String formattedDate = DateFormat('yyyy-MM-dd').format(appointmentDate);
      String formattedDate = Date_Utils.formatDate(appointmentDate);
      String graphDocId =
          '$userId-$formattedDate-${appointmentDate.millisecondsSinceEpoch}';

      // Update the graph status to reflect the cancellation
      await FirebaseFirestore.instance
          .collection('AppointmentGraph')
          .doc(graphDocId)
          .update({
        'status':
            status, // Update the graph data to reflect the canceled appointment
      });

      if (kDebugMode) {
        print('Graph status updated successfully for document $graphDocId.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating graph status: $e');
      }
    }
  }

  //this method is called inside the cancelappointment
  bool _isDateGapSufficient(DateTime currentDate, DateTime availableDate) {
    return availableDate.difference(currentDate).inDays >= 60;
  }

  Future<void> _cancelAppointment(String documentId, DateTime appointmentDate,
      String operationType, String hospitalName) async {
    try {
      final user = currentUser;
      if (user == null) {
        if (kDebugMode) {
          print('User not logged in, cannot cancel appointment');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to cancel appointments')),
        );
        return;
      }
      
      // SECURITY: Verify the appointment belongs to the current user before canceling
      final appointmentDoc = await FirebaseFirestore.instance
          .collection('Appointments')
          .doc(documentId)
          .get();
      
      if (!appointmentDoc.exists) {
        if (kDebugMode) {
          print('Appointment not found: $documentId');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment not found')),
        );
        return;
      }
      
      final appointmentData = appointmentDoc.data()!;
      final appointmentPatientID = appointmentData['patientID'] as String?;
      final appointmentEmail = appointmentData['email'] as String?;
      
      // Verify ownership - prevent patients from canceling other patients' appointments
      if (appointmentPatientID != user.uid || appointmentEmail != user.email) {
        if (kDebugMode) {
          print('SECURITY: Attempt to cancel another patient\'s appointment blocked');
          print('Current user: ${user.uid}, Appointment owner: $appointmentPatientID');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can only cancel your own appointments'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
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
      final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('Appointments')
          .where('status', isEqualTo: 'active')
          .get();

      DateTime currentDate = DateTime.now();
      final DateFormat customDateFormat =
          DateFormat('dd-MM-yyyy'); // Custom date format
      final List<String> deviceTokensToNotify = [];

      // Loop through each appointment.
      for (final doc in querySnapshot.docs) {
        DateTime docAppointmentDate = customDateFormat.parse(doc.get('date'));
        String userId = doc.get('patientID');

        if (_isDateGapSufficient(currentDate, docAppointmentDate)) {
          print(
              'Sufficient gap for user: $userId. Appointment date: $docAppointmentDate');

          // Fetch the token for the user.
          DocumentSnapshot tokenDoc = await FirebaseFirestore.instance
              .collection('TokenData')
              .doc(userId)
              .get();

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
            context: context,
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
      await FirebaseFirestore.instance
          .collection('Appointments')
          .doc(documentId)
          .update({'status': 'cancelled'});
      if (kDebugMode) {
        print('Appointment status updated to cancelled.');
      }

      // NEW: Trigger cascading slot reallocation system
      // This will notify all patients chronologically after the cancelled appointment
      await _appointmentService.handleSlotCancellation(
        cancelledAppointmentId: documentId,
        context: context,
      );

      // Send graph update notifications after cancellation (legacy support).
      Future.delayed(const Duration(milliseconds: 1000), () async {
        for (final token in deviceTokensToNotify) {
          try {
            await _sendGraphNotification(token, context, appointmentDate);
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
    } catch (e) {
      if (kDebugMode) {
        print('Error canceling appointment: $e');
      }
    }
  }

  // Future<void> _cancelAppointment(
  //   String documentId,
  //   DateTime appointmentDate,
  //   String operationType,
  //   String hospitalName,
  // ) async {
  //   try {
  //     // 1. Fetch the current device token.
  //     final String currentToken =
  //         await _notificationServices.getDeviceToken(user!.uid);
  //     print('Current device token: $currentToken');
  //
  //     // 2. Fetch all active appointments.
  //     final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
  //         .collection('Appointments')
  //         .where('status', isEqualTo: 'active')
  //         .get();
  //
  //     DateTime currentDate = DateTime.now();
  //     final DateFormat customDateFormat =
  //         DateFormat('dd-MM-yyyy'); // Custom date format.
  //     final List<String> deviceTokensToNotify = [];
  //
  //     print('Processing ${querySnapshot.docs.length} active appointments.');
  //
  //     // 3. Loop through each appointment to identify eligible notifications.
  //
  //     // for (final doc in querySnapshot.docs) {
  //     //   try {
  //     //     DateTime docAppointmentDate = customDateFormat.parse(doc.get('date'));
  //     //     String userId = doc.get('patientID');
  //     //
  //     //     // Check if the gap between dates is sufficient.
  //     //     if (_isDateGapSufficient(currentDate, docAppointmentDate)) {
  //     //       print(
  //     //           'Sufficient gap for user: $userId. Appointment date: $docAppointmentDate');
  //     //
  //     //       // Fetch the token data for the patient.
  //     //       DocumentSnapshot tokenDoc = await FirebaseFirestore.instance
  //     //           .collection('TokenData')
  //     //           .doc(userId)
  //     //           .get();
  //     //
  //     //       if (tokenDoc.exists) {
  //     //         Map<String, dynamic>? data =
  //     //             tokenDoc.data() as Map<String, dynamic>?;
  //     //         if (data != null && data.containsKey('deviceToken')) {
  //     //           String deviceToken = data['deviceToken'].toString();
  //     //
  //     //           // Add token if it's not the current device's token.
  //     //           if (deviceToken != currentToken) {
  //     //             print('Adding token for user: $userId');
  //     //             deviceTokensToNotify.add(deviceToken);
  //     //           } else {
  //     //             print('Skipping token for current device.');
  //     //           }
  //     //         } else {
  //     //           print('Warning: "deviceToken" field missing for user: $userId');
  //     //         }
  //     //       } else {
  //     //         print('Token document not found for user: $userId');
  //     //       }
  //     //     }
  //     //   } catch (e) {
  //     //     print('Error processing document ${doc.id}: $e');
  //     //   }
  //     // }
  //
  //     for (final doc in querySnapshot.docs) {
  //       DateTime docAppointmentDate = customDateFormat.parse(doc.get('date'));
  //       String userId = doc.get('patientID');
  //
  //       // Check the gap.
  //       if (_isDateGapSufficient(currentDate, docAppointmentDate)) {
  //         print('Sufficient gap for user: $userId.');
  //
  //         DocumentSnapshot tokenDoc = await FirebaseFirestore.instance
  //             .collection('TokenData')
  //             .doc(userId)
  //             .get();
  //
  //         if (tokenDoc.exists) {
  //           Map<String, dynamic>? data =
  //               tokenDoc.data() as Map<String, dynamic>?;
  //           if (data != null && data.containsKey('deviceToken')) {
  //             String deviceToken = data['deviceToken'].toString();
  //             print('Token for $userId: $deviceToken');
  //
  //             if (deviceToken != currentToken) {
  //               deviceTokensToNotify.add(deviceToken);
  //             }
  //           } else {
  //             print('No deviceToken found for user: $userId');
  //           }
  //         } else {
  //           print('Token document not found for user: $userId');
  //         }
  //       }
  //     }
  //
  //     print('Total tokens to notify: ${deviceTokensToNotify.length}');
  //
  //     // 4. Send cancellation notifications to all collected tokens.
  //     for (final token in deviceTokensToNotify) {
  //       try {
  //         await _pushNotificationServices.sendNotificationToUser(
  //           deviceToken: token,
  //           title: 'Appointment Cancellation',
  //           body:
  //               'An appointment has been canceled. Check the graph for available slots.',
  //           data: {
  //             'type': 'appointment_cancellation',
  //             'operationType': operationType,
  //             'hospital': hospitalName,
  //             'appointmentDate': appointmentDate.toIso8601String(),
  //           },
  //           context: context,
  //         );
  //         print('Notification sent to token: $token');
  //       } catch (e) {
  //         print('Error sending notification to $token: $e');
  //       }
  //     }
  //
  //     // 5. Send graph update notifications with a slight delay.
  //     for (final token in deviceTokensToNotify) {
  //       try {
  //         await Future.delayed(
  //             const Duration(milliseconds: 500)); // Small delay.
  //         await _sendGraphNotification(token, context, appointmentDate);
  //         print('Graph notification sent to $token');
  //       } catch (e) {
  //         print('Error sending graph notification to $token: $e');
  //       }
  //     }
  //
  //     // 6. Update the appointment status to 'cancelled' in the database.
  //     await FirebaseFirestore.instance
  //         .collection('Appointments')
  //         .doc(documentId)
  //         .update({'status': 'cancelled'});
  //     print('Appointment status updated to cancelled.');
  //
  //     // 7. Optional: Delete the appointment if necessary.
  //     // Uncomment the following lines if you need to delete the cancelled appointment.
  //     // DocumentSnapshot updatedDoc = await FirebaseFirestore.instance
  //     //     .collection('Appointments')
  //     //     .doc(documentId)
  //     //     .get();
  //     // if (updatedDoc.exists && updatedDoc.get('status') == 'cancelled') {
  //     //   await FirebaseFirestore.instance.collection('Appointments').doc(documentId).delete();
  //     //   print('Appointment with ID $documentId deleted successfully.');
  //     // }
  //
  //     // 8. Update the graph with the cancelled appointment.
  //     await _updateGraphStatus(user!.uid, 'cancelled', appointmentDate);
  //     print('Graph status updated successfully.');
  //   } catch (e) {
  //     print('Error canceling appointment: $e');
  //   }
  // }

  //this method is called inside the _showConfiremCancelDialog method
  // Future<void> _cancelAppointment(String documentId, DateTime appointmentDate,
  //     String operationType, String hospitalName) async {
  //   try {
  //     final String currentToken =
  //         await _notificationServices.getDeviceToken(user!.uid);
  //
  //     // Fetch all active appointments
  //     final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
  //         .collection('Appointments')
  //         .where('status', isEqualTo: 'active')
  //         .get();
  //
  //     DateTime currentDate = DateTime.now();
  //     final DateFormat customDateFormat =
  //         DateFormat('dd-MM-yyyy'); // Define the custom date format
  //     final List<String> deviceTokensToNotify = [];
  //
  //     // Loop through each appointment
  //     for (final doc in querySnapshot.docs) {
  //       DateTime appointmentDate = customDateFormat.parse(doc.get('date'));
  //
  //       if (_isDateGapSufficient(currentDate, appointmentDate)) {
  //         String userId = doc.get('patientID');
  //
  //         DocumentSnapshot tokenDoc = await FirebaseFirestore.instance
  //             .collection('TokenData')
  //             .doc(userId)
  //             .get();
  //
  //         if (tokenDoc.exists) {
  //           Map<String, dynamic>? data =
  //               tokenDoc.data() as Map<String, dynamic>?;
  //           if (data != null && data.containsKey('deviceToken')) {
  //             String deviceToken = data['deviceToken'].toString();
  //
  //             if (deviceToken != currentToken) {
  //               deviceTokensToNotify.add(deviceToken);
  //             }
  //           } else {
  //             print(
  //                 'Warning: "deviceToken" field is missing for user: $userId');
  //           }
  //         }
  //       }
  //     }
  //
  //     // Send cancellation notifications more then 60 days gape
  //     for (final token in deviceTokensToNotify) {
  //       try {
  //         await _pushNotificationServices.sendNotificationToUser(
  //           deviceToken: token,
  //           title: 'Appointment Cancellation',
  //           body:
  //               'An appointment has been canceled. Check the graph for available slots.',
  //           data: {
  //             'type': 'appointment_cancellation',
  //             'operationType': operationType,
  //             'hospital': hospitalName,
  //             'appointmentDate': appointmentDate.toIso8601String(),
  //           },
  //           context: context,
  //         );
  //         print('Notification sent to token : $token');
  //       } catch (e) {
  //         print('Error sending notificaion to $token: $e');
  //       }
  //     }
  //
  //     // Send graph update notification after cancellation
  //     Future.delayed(const Duration(milliseconds: 1000), () async {
  //       for (final token in deviceTokensToNotify) {
  //         try {
  //           await _sendGraphNotification(token, context, appointmentDate);
  //           print('Graph notification sent to $token');
  //         } catch (e) {
  //           print('Error sending graph notification: $e');
  //         }
  //       }
  //     });
  //
  //     // Update the appointment status to 'cancelled' in Appointments collection
  //     await FirebaseFirestore.instance
  //         .collection('Appointments')
  //         .doc(documentId)
  //         .update({'status': 'cancelled'});
  //
  //     // DocumentSnapshot updatedDoc = await FirebaseFirestore.instance
  //     //     .collection('Appointments')
  //     //     .doc(documentId)
  //     //     .get();
  //
  //     //the cancel appointment is not deleted
  //
  //     // if (updatedDoc.exists && updatedDoc.get('status') == 'cancelled') {
  //     //   await FirebaseFirestore.instance
  //     //       .collection('Appointments')
  //     //       .doc(documentId)
  //     //       .delete();
  //     //   print('Appointment with ID $documentId deleted successfully.');
  //     // }
  //
  //     // Update the graph with the canceled appointment
  //     await _updateGraphStatus(user!.uid, 'cancelled', appointmentDate);
  //   } catch (e) {
  //     print('Error canceling appointment: $e');
  //   }
  // }

  //this method is called inside the showCancelAppointmentDetails.
  // Future<void> _showConfirmCancelDialog(String documentId) async {
  //   try {
  //     DocumentSnapshot appointmentDoc = await FirebaseFirestore.instance
  //         .collection('Appointments')
  //         .doc(documentId)
  //         .get();
  //
  //     if (appointmentDoc.exists) {
  //       dynamic dateField = appointmentDoc.get('date');
  //
  //       DateTime appointmentDate;
  //       if (dateField is Timestamp) {
  //         appointmentDate = (dateField as Timestamp).toDate();
  //       } else if (dateField is String) {
  //         appointmentDate =
  //             Date_Utils.parseDate(dateField); // Using the custom date parser
  //       } else {
  //         throw Exception("Unexpected type for appointment date.");
  //       }
  //
  //       showDialog(
  //         context: context,
  //         builder: (BuildContext context) {
  //           return AlertDialog(
  //             backgroundColor: AppColors.blueAccent,
  //             title: const Text('Confirm Cancellation',
  //                 style: TextStyle(color: AppColors.whiteColor)),
  //             content: const Text(
  //                 'Are you sure you want to cancel this appointment?',
  //                 style: TextStyle(color: AppColors.whiteColor)),
  //             actions: <Widget>[
  //               buildDialogButton('No', () {
  //                 Navigator.of(context).pop();
  //               }),
  //               buildDialogButton('Yes', () async {
  //                 await _cancelAppointment(
  //                   documentId,
  //                   appointmentDate,
  //                 );
  //                 Navigator.of(context).pop();
  //               }),
  //             ],
  //           );
  //         },
  //       );
  //     } else {
  //       print('Error: Appointment document not found.');
  //     }
  //   } catch (e) {
  //     print('Error in _showConfirmCancelDialog: $e');
  //   }
  // }

  Future<void> _showConfirmCancelDialog(String documentId) async {
    try {
      DocumentSnapshot appointmentDoc = await FirebaseFirestore.instance
          .collection('Appointments')
          .doc(documentId)
          .get();

      if (appointmentDoc.exists) {
        // Extract fields from the document.
        dynamic dateField = appointmentDoc.get('date');
        String hospitalName = appointmentDoc.get('hospital');
        String operationType = appointmentDoc.get('operationType');

        DateTime appointmentDate;

        // Parse the appointment date based on the type.
        if (dateField is Timestamp) {
          appointmentDate = dateField.toDate();
        } else if (dateField is String) {
          appointmentDate = Date_Utils.parseDate(dateField);
        } else {
          throw Exception("Unexpected type for appointment date.");
        }

        // Show the confirmation dialog.
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: AppColors.blueAccent,
              title: const Text(
                'Confirm Cancellation',
                style: TextStyle(color: AppColors.whiteColor),
              ),
              content: const Text(
                'Are you sure you want to cancel this appointment?',
                style: TextStyle(color: AppColors.whiteColor),
              ),
              actions: <Widget>[
                buildDialogButton('No', () {
                  Navigator.of(context).pop(); // Close the dialog.
                }),
                buildDialogButton('Yes', () async {
                  // Close the dialog first to avoid UI freeze.
                  Navigator.of(context).pop();

                  // Delay the cancel operation to ensure smooth dialog transition.
                  Future.delayed(Duration(milliseconds: 200), () async {
                    await _cancelAppointment(
                      documentId,
                      appointmentDate,
                      hospitalName,
                      operationType,
                    );
                  });
                }),
              ],
            );
          },
        );
      } else {
        if (kDebugMode) {
          print('Error: Appointment document not found.');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in _showConfirmCancelDialog: $e');
      }
    }
  }

  // cancel the appointment dailog...
  Future<void> showCancelledAppointmentDetails(String documentId) async {
    final user = currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to view appointments')),
      );
      return;
    }
    
    DocumentSnapshot appointmentDoc = await FirebaseFirestore.instance
        .collection('Appointments')
        .doc(documentId)
        .get();

    if (!appointmentDoc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment not found')),
      );
      return;
    }
    
    // SECURITY: Verify the appointment belongs to the current user
    final appointmentData = appointmentDoc.data() as Map<String, dynamic>?;
    if (appointmentData == null) {
      return;
    }
    
    final appointmentPatientID = appointmentData['patientID'] as String?;
    final appointmentEmail = appointmentData['email'] as String?;
    
    // Prevent viewing other patients' appointments
    if (appointmentPatientID != user.uid || appointmentEmail != user.email) {
      if (kDebugMode) {
        print('SECURITY: Attempt to view another patient\'s appointment blocked');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only view your own appointments'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (appointmentDoc.exists) {
      String date = appointmentData['date'].toString();
      String email = appointmentData['email'];
      String name = appointmentData['name'];

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: AppColors.blueAccent,
            title: const Text(
              'Cancelled Appointment Details',
              style: TextStyle(color: AppColors.whiteColor),
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Date: ${Date_Utils.formatDate(Date_Utils.parseDate(date))}', // Format the date properly
                  style: const TextStyle(color: AppColors.whiteColor),
                ),
                Text('Email: $email',
                    style: const TextStyle(color: AppColors.whiteColor)),
                Text('Name: $name',
                    style: const TextStyle(color: AppColors.whiteColor)),
              ],
            ),
            actions: <Widget>[
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                },
                child: Container(
                  height: 40,
                  width: 110,
                  decoration: BoxDecoration(
                      color: AppColors.appColor,
                      borderRadius: BorderRadius.circular(40)),
                  child: const Center(
                    child: Text(
                      'Close',
                      style: TextStyle(color: AppColors.whiteColor),
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  _showConfirmCancelDialog(documentId);
                },
                child: Container(
                  height: 40,
                  width: 110,
                  decoration: BoxDecoration(
                      color: AppColors.appColor,
                      borderRadius: BorderRadius.circular(40)),
                  child: const Center(
                    child: Text(
                      'Confirm',
                      style: TextStyle(color: AppColors.whiteColor),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> showAvailableDatesDialog() async {
    try {
      final user = currentUser;
      if (user == null || user.email == null) {
        return;
      }
      
      // SECURITY: Filter by patientID to ensure patient-specific appointments
      QuerySnapshot userAppointmentsSnapshot = await FirebaseFirestore.instance
          .collection('Appointments')
          .where('patientID', isEqualTo: user.uid)
          .where('email', isEqualTo: user.email)
          .where('status', isEqualTo: 'active')
          .get();

      if (userAppointmentsSnapshot.docs.isEmpty) {
        if (kDebugMode) {
          print("No active appointments found for the user.");
        }
      }

      List<DateTime> userAppointmentDates =
          userAppointmentsSnapshot.docs.map((doc) {
        if (kDebugMode) {
          print("Active appointment date: ${doc['date']}");
        }
        return Date_Utils.parseDate(doc['date']);
      }).toList();

      QuerySnapshot cancelledAppointmentsSnapshot = await FirebaseFirestore
          .instance
          .collection('Appointments')
          .where('status', isEqualTo: 'cancelled')
          .get();

      if (cancelledAppointmentsSnapshot.docs.isEmpty) {
        if (kDebugMode) {
          print("No canceled appointments found.");
        }
      }

      List<DateTime> availableDates =
          cancelledAppointmentsSnapshot.docs.map((doc) {
        if (kDebugMode) {
          print("Canceled appointment date: ${doc['date']}");
        }
        return Date_Utils.parseDate(doc['date']);
      }).toList();

      List<String> filteredDates = [];

      for (var availableDate in availableDates) {
        for (var userAppointmentDate in userAppointmentDates) {
          if (_isDateGapSufficient(userAppointmentDate, availableDate)) {
            if (kDebugMode) {
              print("Available appointment with sufficient gap: $availableDate");
            }
            filteredDates.add(Date_Utils.formatDate(availableDate));
            break;
          }
        }
      }

      if (filteredDates.isNotEmpty) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: AppColors.whiteColor,
              title: const Text(
                'More Dates Available Now',
                style: TextStyle(color: AppColors.blackColor),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: filteredDates
                    .map((date) => ListTile(
                          title: Text(date),
                          onTap: () {
                            Navigator.of(context).pop();
                            showSelectCurrentAppointmentDialog(context, date);
                          },
                        ))
                    .toList(),
              ),
              actions: <Widget>[
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    height: 40,
                    width: 110,
                    decoration: BoxDecoration(
                        color: AppColors.appColor,
                        borderRadius: BorderRadius.circular(40)),
                    child: const Center(
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: AppColors.whiteColor),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      } else {
        if (kDebugMode) {
          print("No available dates to show.");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error showing available dates: $e");
      }
    }
  }

  Future<void> eSelectedAppointment(DateTime selectedDate) async {
    final user = currentUser;
    if (user == null || user.email == null) {
      return;
    }
    
    // SECURITY: Find the appointment to update - filter by patientID
    QuerySnapshot appointmentsToUpdate = await FirebaseFirestore.instance
        .collection('Appointments')
        .where('patientID', isEqualTo: user.uid)
        .where('email', isEqualTo: user.email)
        .where('date', isEqualTo: Date_Utils.formatDate(selectedDate))
        .where('status', isEqualTo: 'active')
        .get();

    if (appointmentsToUpdate.docs.isNotEmpty) {
      // Update the first found document (assuming there's only one active appointment per date per user)
      String documentId = appointmentsToUpdate.docs.first.id;
      await FirebaseFirestore.instance
          .collection('Appointments')
          .doc(documentId)
          .update({'status': 'cancelled'});

      // Optionally update other fields as needed
    } else {
      // Handle case where no appointment was found for the selected date
      if (kDebugMode) {
        print('No active appointment found for the selected date.');
      }
    }
  }

  Future<void> showSelectCurrentAppointmentDialog(
      BuildContext context, String selectedAvailableDate) async {
    final user = currentUser;
    if (user == null || user.email == null) {
      return;
    }
    
    // SECURITY: Fetch user's active appointments - filter by patientID
    QuerySnapshot userAppointmentsSnapshot = await FirebaseFirestore.instance
        .collection('Appointments')
        .where('patientID', isEqualTo: user.uid)
        .where('email', isEqualTo: user.email)
        .where('status', isEqualTo: 'active')
        .get();

    List<DocumentSnapshot> userAppointments = userAppointmentsSnapshot.docs;

    if (userAppointments.isNotEmpty) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            backgroundColor: AppColors.whiteColor,
            title: const Text(
              'Select Appointment to Reschedule',
              style: TextStyle(color: AppColors.blackColor),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: userAppointments.map((doc) {
                String appointmentDate = doc['date'];
                return ListTile(
                  title: Text(Date_Utils.formatDate(
                      DateTime.parse(appointmentDate))), // Format the date
                  //title: Text(dateFormat.format(DateTime.parse(appointmentDate))), // Format the date
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UpdateAppointmentScreen(
                          selectedAvailableDate: selectedAvailableDate,
                          currentAppointmentId: doc.id,
                          user: currentUser,
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
            actions: <Widget>[
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                },
                child: Container(
                  height: 40,
                  width: 110,
                  decoration: BoxDecoration(
                      color: AppColors.appColor,
                      borderRadius: BorderRadius.circular(40)),
                  child: const Center(
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.whiteColor),
                    ),
                  ),
                ),
              ),

              // TextButton(
              //   onPressed: () {
              //     Navigator.of(context).pop();
              //   },
              //   child: Text('Cancel'),
              // ),
            ],
          );
        },
      );
    }
  }

  //logout in the title bar option
  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacement(
        context,
        CupertinoPageRoute(builder: (context) => const SelectionView()),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error during logout: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AAFIA App',
          style: TextStyle(color: AppColors.whiteColor),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.whiteColor),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Scrollable advertisement cards section
          // SizedBox(
          //   height: 200, // Adjust the height according to your preference
          //   child: SingleChildScrollView(
          //     scrollDirection: Axis.horizontal,
          //     child: Row(
          //       children: [
          //         advertisementCard(
          //           imageUrl: 'https://via.placeholder.com/150',
          //           title: 'Special Offer 1',
          //           description: 'Details for special offer 1',
          //         ),
          //         advertisementCard(
          //           imageUrl: 'https://via.placeholder.com/150',
          //           title: 'Special Offer 2',
          //           description: 'Details for special offer 2',
          //         ),
          //         advertisementCard(
          //           imageUrl: 'https://via.placeholder.com/150',
          //           title: 'Special Offer 3',
          //           description: 'Details for special offer 3',
          //         ),
          //       ],
          //     ),
          //   ),
          // ),

          SizedBox(
            height: 30,
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getAppointments(),
              builder: (BuildContext context,
                  AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Something went wrong',
                      style: TextStyle(color: AppColors.redColor),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.blackColor),
                  );
                }

                if (snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No active appointments found',
                      style: TextStyle(color: AppColors.blackColor),
                    ),
                  );
                }

                // Convert to AppointmentData and filter out past appointments
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                
                final futureAppointments = snapshot.data!.docs
                    .map((doc) {
                      try {
                        final data = doc.data() as Map<String, dynamic>;
                        final dateString = data['date'] as String? ?? '';
                        final parsedDate = Date_Utils.parseDate(dateString);
                        final appointmentDateOnly = DateTime(
                          parsedDate.year,
                          parsedDate.month,
                          parsedDate.day,
                        );
                        // Only include appointments from today onwards
                        if (!appointmentDateOnly.isBefore(today)) {
                          return doc;
                        }
                        return null;
                      } catch (e) {
                        return null;
                      }
                    })
                    .where((doc) => doc != null)
                    .cast<DocumentSnapshot>()
                    .toList();

                if (futureAppointments.isEmpty) {
                  return const Center(
                    child: Text(
                      'No upcoming appointments found',
                      style: TextStyle(color: AppColors.blackColor),
                    ),
                  );
                }

                // Extract the last appointment's data for the bottom sheet
                DocumentSnapshot lastDocument = futureAppointments.last;
                Map<String, dynamic> lastAppointmentData =
                    lastDocument.data()! as Map<String, dynamic>;
                String lastAppointmentDate = lastAppointmentData['date'];
                String lastAppointmentTime = lastAppointmentData['time'];
                String lastStatus = lastAppointmentData['status'];

                return Column(
                  children: [
                    ListView(
                      shrinkWrap: true,
                      children:
                          futureAppointments.map((DocumentSnapshot document) {
                        Map<String, dynamic> data =
                            document.data()! as Map<String, dynamic>;
                        String appointmentDate =
                            data['date']; // Get appointment date
                        String appointmentTime =
                            data['time']; // Get appointment time

                        // Parse the appointment date using DateUtils
                        DateTime parsedDate =
                            Date_Utils.parseDate(appointmentDate);

                        String appointmentStatus = data['status'] ?? 'active';
                        
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Card(
                            color: Colors.grey.withOpacity(0.2),
                            child: ListTile(
                              title: Text(
                                'Appointment Date: ${Date_Utils.formatDate(parsedDate)}',
                                style: const TextStyle(
                                    color: AppColors.blueAccent,
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Time: $appointmentTime',
                                      style: const TextStyle(
                                          color: AppColors.blueAccent,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  StatusBadge(status: appointmentStatus),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.cancel,
                                    color: AppColors.redColor),
                                onPressed: () {
                                  showCancelledAppointmentDetails(document.id);
                                },
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    // Add bottom sheet at the end with the latest appointment details
                    buildPersistentBottomSheet(
                      context,
                      lastAppointmentDate, // Pass the appointment date
                      lastAppointmentTime, // Pass the appointment time
                      lastStatus, // Pass the appointment status
                    ),
                  ],
                );
              },
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const AddAppointmentScreen()),
          );
        },
        child: const Icon(
          Icons.add,
          color: Colors.white,
        ),
      ),
      // bottomSheet: _buildPersistentBottomSheet(context), // Persistent bottom sheet here
    );
  }
}
