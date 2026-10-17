import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../notification/notification_services.dart';
import '../../notification/push_notification_services.dart';
import '../../repositories/patient_appointments_repository.dart';
import '../../utils/date_utils.dart';
import '../selection_view.dart';
import 'add-appoinment.dart';
import 'home/appointment_list.dart';
import 'home/cancel_appointment_dialogs.dart';
import 'home/date_gap.dart';
import 'home/patient_home_app_bar.dart';
import 'home/patient_home_notification_service.dart';
import 'home/reminder_dialog.dart';
import 'home/reschedule_dialogs.dart';
import 'home/upcoming_appointment_check.dart';

class PatientHomeViewNew extends StatefulWidget {
  const PatientHomeViewNew({super.key});

  @override
  State<PatientHomeViewNew> createState() => _PatientHomeViewNewState();
}

class _PatientHomeViewNewState extends State<PatientHomeViewNew> {
  final NotificationServices _notificationServices = NotificationServices();
  final PushNotificationServices _pushNotificationServices =
      PushNotificationServices();

  late final PatientHomeNotificationService _homeNotifications =
      PatientHomeNotificationService(
    repository: _repository,
    notificationServices: _notificationServices,
    pushNotificationServices: _pushNotificationServices,
  );

  // Read once (first used in initState) so later uses never touch context.
  late final PatientAppointmentsRepository _repository =
      context.read<PatientAppointmentsRepository>();

  // Use local user instead of global to ensure it's always current
  User? get currentUser => FirebaseAuth.instance.currentUser;

  // Removed _dialogShown flag - dialog should show every time app opens if appointment is within 10 days

  @override
  void initState() {
    super.initState();

    if (kDebugMode) {
      print('initState is running .......');
    }
    _homeNotifications.initializeNotifications(currentUser);

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

  Future<void> _checkUpcomingAppointments() {
    return checkUpcomingAppointments(
      user: currentUser,
      repository: _repository,
      isMounted: () => mounted,
      showReminder: (operationType, hospitalName, appointmentDate,
          appointmentId) {
        _showAppointmentConfirmationDialog(
          context,
          operationType,
          hospitalName,
          appointmentDate,
          appointmentId,
        );
      },
      sendUpcomingNotification:
          (patientName, operationType, hospitalName, appointmentDate) {
        _homeNotifications.sendUpcomingAppointmentNotification(
          user: currentUser,
          contextOf: () => context,
          patientName: patientName,
          operationType: operationType,
          hospitalName: hospitalName,
          appointmentDate: appointmentDate,
        );
      },
    );
  }

// Show this dialog when appointment is 10 days or less away
  void _showAppointmentConfirmationDialog(
      BuildContext context,
      String operationType,
      String hospitalName,
      DateTime appointmentDate,
      String appointmentId) {
    showAppointmentReminderDialog(
      context: context,
      operationType: operationType,
      hospitalName: hospitalName,
      appointmentDate: appointmentDate,
      appointmentId: appointmentId,
      repository: _repository,
      currentUser: () => currentUser,
      isMounted: () => mounted,
      onCancelAppointment: () => _cancelAppointment(
          appointmentId, appointmentDate, operationType, hospitalName),
      onShowAvailableDates: showAvailableDatesDialog,
    );
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
      final appointmentDoc = await _repository.getAppointment(documentId);

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

      // Notify other patients, set status to 'cancelled', update the graph.
      await _homeNotifications.cancelAppointmentAndNotify(
        user: user,
        documentId: documentId,
        appointmentDate: appointmentDate,
        operationType: operationType,
        hospitalName: hospitalName,
        contextOf: () => context,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error canceling appointment: $e');
      }
    }
  }

  Future<void> _showConfirmCancelDialog(String documentId) async {
    try {
      DocumentSnapshot appointmentDoc =
          await _repository.getAppointment(documentId);

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
        showConfirmCancelDialog(
          context: context,
          onConfirmCancel: () => _cancelAppointment(
            documentId,
            appointmentDate,
            operationType,
            hospitalName,
          ),
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

    DocumentSnapshot appointmentDoc =
        await _repository.getAppointment(documentId);

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

      showCancelledAppointmentDetailsDialog(
        context: context,
        date: date,
        email: email,
        name: name,
        onConfirm: () {
          _showConfirmCancelDialog(documentId);
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
      QuerySnapshot userAppointmentsSnapshot = await _repository
          .getMyBookedAppointments(uid: user.uid, email: user.email);

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

      QuerySnapshot cancelledAppointmentsSnapshot =
          await _repository.getCancelledAppointments();

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
          if (isDateGapSufficient(userAppointmentDate, availableDate)) {
            if (kDebugMode) {
              print("Available appointment with sufficient gap: $availableDate");
            }
            filteredDates.add(Date_Utils.formatDate(availableDate));
            break;
          }
        }
      }

      if (filteredDates.isNotEmpty) {
        showAvailableDatesListDialog(
          context: context,
          filteredDates: filteredDates,
          onDateSelected: (_, date) {
            // Use the screen's context: the dates dialog has just closed
            if (mounted) showSelectCurrentAppointmentDialog(context, date);
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

  Future<void> showSelectCurrentAppointmentDialog(
      BuildContext context, String selectedAvailableDate) async {
    final user = currentUser;
    if (user == null || user.email == null) {
      return;
    }

    // SECURITY: Fetch user's active appointments - filter by patientID
    QuerySnapshot userAppointmentsSnapshot = await _repository
        .getMyBookedAppointments(uid: user.uid, email: user.email);

    List<DocumentSnapshot> userAppointments = userAppointmentsSnapshot.docs;

    if (userAppointments.isNotEmpty && context.mounted) {
      showSelectAppointmentToRescheduleDialog(
        context: context,
        userAppointments: userAppointments,
        selectedAvailableDate: selectedAvailableDate,
        currentUser: () => currentUser,
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
    final user = currentUser;
    return Scaffold(
      appBar: buildPatientHomeAppBar(onLogout: _logout),
      body: Column(
        children: [
          SizedBox(
            height: 30,
          ),

          Expanded(
            child: PatientAppointmentList(
              // SECURITY: Filter by both email AND patientID to ensure patient-specific appointments
              stream: _repository.watchMyBookedAppointments(
                uid: user?.uid,
                email: user?.email,
              ),
              onCancelPressed: (documentId) {
                showCancelledAppointmentDetails(documentId);
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
    );
  }
}
