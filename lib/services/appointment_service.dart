import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../notification/push_notification_services.dart';
import '../utils/date_utils.dart';

/// Appointment model for chronological queue management
class Appointment {
  final String documentId;
  final String patientID;
  final String email;
  final String name;
  final DateTime appointmentDateTime; // Combined date + time
  final String date; // Formatted date string 'dd-MM-yyyy'
  final String time; // Formatted time string 'HH:mm'
  final String status;
  final String? hospital;
  final String? operationType;

  Appointment({
    required this.documentId,
    required this.patientID,
    required this.email,
    required this.name,
    required this.appointmentDateTime,
    required this.date,
    required this.time,
    required this.status,
    this.hospital,
    this.operationType,
  });

  factory Appointment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final dateStr = data['date'] as String;
    final timeStr = data['time'] as String;

    // Parse date
    final parsedDate = Date_Utils.parseDate(dateStr);
    
    // Parse time - handle both 'HH:mm' (24-hour) and 'hh:mm a' (12-hour) formats
    DateTime parsedTime;
    try {
      // Try 24-hour format first (HH:mm)
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          final hour = int.parse(parts[0].trim());
          final minute = int.parse(parts[1].split(' ')[0].trim());
          parsedTime = DateTime(2000, 1, 1, hour, minute);
        } else {
          parsedTime = Date_Utils.parseTime(timeStr);
        }
      } else {
        parsedTime = Date_Utils.parseTime(timeStr);
      }
    } catch (e) {
      // Fallback to Date_Utils parser
      parsedTime = Date_Utils.parseTime(timeStr);
    }

    // Create combined DateTime
    final appointmentDateTime = DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      parsedTime.hour,
      parsedTime.minute,
    );

    return Appointment(
      documentId: doc.id,
      patientID: data['patientID'] as String? ?? '',
      email: data['email'] as String? ?? '',
      name: data['name'] as String? ?? '',
      appointmentDateTime: appointmentDateTime,
      date: dateStr,
      time: timeStr,
      status: data['status'] as String? ?? 'active',
      hospital: data['hospital'] as String?,
      operationType: data['operationType'] as String?,
    );
  }
}

/// Service class for managing appointments and cascading slot reallocation
class AppointmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PushNotificationServices _pushNotificationServices =
      PushNotificationServices();

  /// Get all active appointments sorted chronologically (by date + time)
  Future<List<Appointment>> getChronologicalQueue() async {
    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('Appointments')
          .where('status', isEqualTo: 'active')
          .get();

      final List<Appointment> appointments = snapshot.docs
          .map((doc) => Appointment.fromFirestore(doc))
          .toList();

      // Sort by appointmentDateTime (chronological order)
      appointments.sort((a, b) =>
          a.appointmentDateTime.compareTo(b.appointmentDateTime));

      return appointments;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting chronological queue: $e');
      }
      return [];
    }
  }

  /// Find the index of an appointment in the chronological queue
  int? findAppointmentIndex(
      List<Appointment> queue, String appointmentDocumentId) {
    for (int i = 0; i < queue.length; i++) {
      if (queue[i].documentId == appointmentDocumentId) {
        return i;
      }
    }
    return null;
  }

  /// Get all patients scheduled chronologically after a specific appointment
  /// This works even if the appointment is already cancelled
  Future<List<Appointment>> getPatientsAfterAppointment(
      String cancelledAppointmentId) async {
    try {
      // Get the cancelled appointment details first (even if status is 'cancelled')
      final cancelledDoc = await _firestore
          .collection('Appointments')
          .doc(cancelledAppointmentId)
          .get();

      if (!cancelledDoc.exists) {
        if (kDebugMode) {
          print('Cancelled appointment document not found: $cancelledAppointmentId');
        }
        return [];
      }

      final cancelledData = cancelledDoc.data()!;
      final cancelledDate = cancelledData['date'] as String;
      final cancelledTime = cancelledData['time'] as String;

      // Parse the cancelled appointment's date and time
      final cancelledDateTime = DateTime(
        Date_Utils.parseDate(cancelledDate).year,
        Date_Utils.parseDate(cancelledDate).month,
        Date_Utils.parseDate(cancelledDate).day,
        _parseTimeString(cancelledTime).hour,
        _parseTimeString(cancelledTime).minute,
      );

      // Get all active appointments and filter those after the cancelled one
      final queue = await getChronologicalQueue();
      
      // Return all appointments that are chronologically after the cancelled one
      return queue.where((appointment) {
        return appointment.appointmentDateTime.isAfter(cancelledDateTime);
      }).toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting patients after appointment: $e');
      }
      return [];
    }
  }

  /// Get device token for a patient
  Future<String?> getPatientDeviceToken(String patientId) async {
    try {
      final doc = await _firestore.collection('TokenData').doc(patientId).get();
      if (doc.exists) {
        final data = doc.data();
        return data?['deviceToken'] as String?;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting device token: $e');
      }
      return null;
    }
  }

  /// Send slot available notification to eligible patients
  Future<void> sendSlotAvailableNotification({
    required String availableDate,
    required String availableTime,
    required String hospital,
    required String operationType,
    required List<Appointment> eligiblePatients,
    required BuildContext context,
  }) async {
    if (kDebugMode) {
      print(
          'Sending slot available notification to ${eligiblePatients.length} patients');
    }

    for (final patient in eligiblePatients) {
      try {
        final deviceToken = await getPatientDeviceToken(patient.patientID);
        if (deviceToken == null) {
          if (kDebugMode) {
            print('No device token found for patient ${patient.patientID}');
          }
          continue;
        }

        final success = await _pushNotificationServices.sendNotificationToUser(
          deviceToken: deviceToken,
          title: 'Earlier Appointment Slot Available',
          body:
              'An earlier appointment slot has become available on $availableDate at $availableTime for $operationType at $hospital. You can claim this slot to move your appointment forward. Tap to view details.',
          data: {
            'type': 'slot_available',
            'availableDate': availableDate,
            'availableTime': availableTime,
            'hospital': hospital,
            'operationType': operationType,
            'slotDocumentId': '', // Will be set when slot is claimed
          },
          context: context,
        );

        if (kDebugMode) {
          if (success) {
            print('Slot available notification sent to ${patient.email}');
          } else {
            print('Failed to send notification to ${patient.email}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error sending notification to ${patient.email}: $e');
        }
      }
    }
  }

  /// Send cascaded slot available notification (when a patient claims a slot)
  Future<void> sendCascadedSlotAvailableNotification({
    required String availableDate,
    required String availableTime,
    required String hospital,
    required String operationType,
    required List<Appointment> eligiblePatients,
    required BuildContext context,
  }) async {
    if (kDebugMode) {
      print(
          'Sending cascaded slot available notification to ${eligiblePatients.length} patients');
    }

    for (final patient in eligiblePatients) {
      try {
        final deviceToken = await getPatientDeviceToken(patient.patientID);
        if (deviceToken == null) {
          if (kDebugMode) {
            print('No device token found for patient ${patient.patientID}');
          }
          continue;
        }

        final success = await _pushNotificationServices.sendNotificationToUser(
          deviceToken: deviceToken,
          title: 'New Appointment Slot Available',
          body:
              'A new appointment slot has become available on $availableDate at $availableTime for $operationType at $hospital. This slot was freed by another patient moving to an earlier appointment. You can claim this slot to move your appointment forward. Tap to view details.',
          data: {
            'type': 'cascaded_slot_available',
            'availableDate': availableDate,
            'availableTime': availableTime,
            'hospital': hospital,
            'operationType': operationType,
            'slotDocumentId': '', // Will be set when slot is claimed
          },
          context: context,
        );

        if (kDebugMode) {
          if (success) {
            print('Cascaded slot notification sent to ${patient.email}');
          } else {
            print('Failed to send cascaded notification to ${patient.email}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error sending cascaded notification to ${patient.email}: $e');
        }
      }
    }
  }

  /// Claim a slot: Create a NEW appointment for the claimed slot (patient will have TWO appointments)
  /// This method creates a new appointment and triggers cascading notifications
  /// The old appointment remains unchanged, allowing the patient to have multiple appointments
  Future<bool> claimSlot({
    required String patientId,
    required String newDate,
    required String newTime,
    required String newHospital,
    required String newOperationType,
    required String oldAppointmentDocumentId,
    required BuildContext context,
  }) async {
    try {
      // First, get the old appointment data BEFORE the transaction
      // This ensures we have the old values for cascading notifications
      final oldAppointmentDocBefore = await _firestore
          .collection('Appointments')
          .doc(oldAppointmentDocumentId)
          .get();

      if (!oldAppointmentDocBefore.exists) {
        if (kDebugMode) {
          print('Old appointment not found: $oldAppointmentDocumentId');
        }
        return false;
      }

      final oldAppointmentDataBefore = oldAppointmentDocBefore.data()!;
      
      // Verify the appointment belongs to this patient
      if (oldAppointmentDataBefore['patientID'] != patientId) {
        if (kDebugMode) {
          print('Appointment does not belong to patient $patientId');
        }
        return false;
      }

      // Verify the appointment is still active
      if (oldAppointmentDataBefore['status'] != 'active') {
        if (kDebugMode) {
          print('Appointment is not active: ${oldAppointmentDataBefore['status']}');
        }
        return false;
      }

      // Store old values for cascading
      final oldDate = oldAppointmentDataBefore['date'] as String;
      final oldTime = oldAppointmentDataBefore['time'] as String;
      final oldHospital = oldAppointmentDataBefore['hospital'] as String? ?? '';
      final oldOperationType = oldAppointmentDataBefore['operationType'] as String? ?? '';

      // Check if the new slot is already taken by another active appointment
      final newSlotQuery = await _firestore
          .collection('Appointments')
          .where('date', isEqualTo: newDate)
          .where('time', isEqualTo: newTime)
          .where('status', isEqualTo: 'active')
          .get();

      // Check if slot is taken by someone else (excluding the old appointment)
      final slotTaken = newSlotQuery.docs.any((doc) {
        return doc.id != oldAppointmentDocumentId;
      });

      if (slotTaken) {
        if (kDebugMode) {
          print('Slot $newDate at $newTime is already taken by another patient');
        }
        // Return a specific error that can be caught and displayed to user
        throw Exception('SLOT_ALREADY_TAKEN');
      }

      // Use a transaction to ensure atomicity and prevent race conditions
      // Create a NEW appointment for the claimed slot (patient will have TWO appointments)
      final transactionSuccess = await _firestore.runTransaction((transaction) async {
        // Re-verify the old appointment within transaction (double-check pattern)
        final appointmentDoc = await transaction.get(
          _firestore.collection('Appointments').doc(oldAppointmentDocumentId),
        );

        if (!appointmentDoc.exists) {
          if (kDebugMode) {
            print('Transaction: Old appointment document does not exist');
          }
          return false;
        }

        final appointmentData = appointmentDoc.data()!;
        
        // Verify still belongs to patient and is active
        if (appointmentData['patientID'] != patientId ||
            appointmentData['status'] != 'active') {
          if (kDebugMode) {
            print('Transaction: Appointment validation failed - patientID: ${appointmentData['patientID']}, status: ${appointmentData['status']}');
          }
          return false;
        }

        // Create a unique document ID for the new appointment
        String dateStr = newDate.replaceAll('-', '');
        String timeStr = newTime.replaceAll(':', '-').replaceAll(' ', '-');
        String newDocId = '$patientId-$dateStr-$timeStr-${DateTime.now().millisecondsSinceEpoch}';

        if (kDebugMode) {
          print('Transaction: Creating new appointment with ID: $newDocId');
        }

        // Calculate days moved
        final oldDateTime = Date_Utils.parseDate(oldDate);
        final newDateTime = Date_Utils.parseDate(newDate);
        final daysMoved = newDateTime.isBefore(oldDateTime) 
            ? oldDateTime.difference(newDateTime).inDays 
            : 0;

        // Update OLD appointment with reallocation data
        transaction.update(
          _firestore.collection('Appointments').doc(oldAppointmentDocumentId),
          {
            'reallocationStatus': 'Reallocated',
            'originalDate': oldDate,
            'originalTime': oldTime,
            'daysMoved': daysMoved,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );

        // Create a NEW appointment document (patient will have TWO appointments)
        transaction.set(
          _firestore.collection('Appointments').doc(newDocId),
          {
            'patientID': patientId,
            'email': appointmentData['email'] ?? '',
            'name': appointmentData['name'] ?? '',
            'address': appointmentData['address'] ?? '',
            'location': appointmentData['location'] ?? '',
            'date': newDate,
            'time': newTime,
            'status': 'active',
            'phone': appointmentData['phone'] ?? '',
            'operationType': newOperationType,
            'hospital': newHospital,
            'reallocationStatus': 'Original', // New appointment is original
            'isClaimedSlot': true, // Flag to skip reminders for this appointment
            'skipReminder': true, // Additional flag for clarity
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );

        if (kDebugMode) {
          print('Transaction: New appointment document set successfully');
        }

        return true;
      });

      if (!transactionSuccess) {
        if (kDebugMode) {
          print('Transaction failed: Slot may have been claimed by another patient');
        }
        return false;
      }

      if (kDebugMode) {
        print(
            'Patient $patientId claimed slot: NEW appointment created for $newDate at $newTime (old appointment remains: $oldDate at $oldTime)');
      }

      // After successful transaction, create AppointmentGraph entry for the NEW appointment
      // The old appointment's graph entry should remain unchanged (since old appointment still exists)
      await _createAppointmentGraphEntry(
        patientId: patientId,
        appointmentDate: newDate,
        appointmentTime: newTime,
        hospital: newHospital,
        operationType: newOperationType,
        patientName: oldAppointmentDataBefore['name'] as String? ?? '',
        status: 'active',
      );

      // Get patients scheduled after the old slot (for cascading)
      // Refresh the queue after the update
      final queue = await getChronologicalQueue();
      
      // Find patients after the old slot
      final oldDateTime = DateTime(
        Date_Utils.parseDate(oldDate).year,
        Date_Utils.parseDate(oldDate).month,
        Date_Utils.parseDate(oldDate).day,
        _parseTimeString(oldTime).hour,
        _parseTimeString(oldTime).minute,
      );

      final patientsAfterOldSlot = queue.where((appointment) {
        return appointment.appointmentDateTime.isAfter(oldDateTime) &&
            appointment.patientID != patientId;
      }).toList();

      // Send cascaded slot available notification
      if (patientsAfterOldSlot.isNotEmpty) {
        await sendCascadedSlotAvailableNotification(
          availableDate: oldDate,
          availableTime: oldTime,
          hospital: oldHospital,
          operationType: oldOperationType,
          eligiblePatients: patientsAfterOldSlot,
          context: context,
        );
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error claiming slot: $e');
      }
      return false;
    }
  }

  /// Create a new AppointmentGraph entry for a newly created appointment
  Future<void> _createAppointmentGraphEntry({
    required String patientId,
    required String appointmentDate,
    required String appointmentTime,
    required String hospital,
    required String operationType,
    required String patientName,
    required String status,
  }) async {
    try {
      // Create a unique document ID for the graph entry
      String dateStr = appointmentDate.replaceAll('-', '');
      String timeStr = appointmentTime.replaceAll(':', '-').replaceAll(' ', '-');
      String graphDocId = '$patientId-$dateStr-$timeStr-${DateTime.now().millisecondsSinceEpoch}';

      // Create a new document in AppointmentGraph collection
      await _firestore.collection('AppointmentGraph').doc(graphDocId).set({
        'userId': patientId,
        'appointmentDate': appointmentDate,
        'time': appointmentTime,
        'status': status,
        'patientName': patientName,
        'hospitalName': hospital,
        'operationType': operationType,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('AppointmentGraph entry created for patient $patientId: $appointmentDate at $appointmentTime');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error creating AppointmentGraph entry: $e');
      }
    }
  }

  /// Helper method to parse time string (handles both 24-hour and 12-hour formats)
  DateTime _parseTimeString(String timeStr) {
    try {
      // Try 24-hour format first (HH:mm)
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          final hour = int.parse(parts[0].trim());
          final minute = int.parse(parts[1].split(' ')[0].trim());
          return DateTime(2000, 1, 1, hour, minute);
        }
      }
      // Fallback to Date_Utils parser (12-hour format)
      return Date_Utils.parseTime(timeStr);
    } catch (e) {
      // Final fallback
      return Date_Utils.parseTime(timeStr);
    }
  }

  /// Handle initial slot cancellation - trigger slot available notifications
  Future<void> handleSlotCancellation({
    required String cancelledAppointmentId,
    required BuildContext context,
  }) async {
    try {
      // Get the cancelled appointment details
      final cancelledDoc = await _firestore
          .collection('Appointments')
          .doc(cancelledAppointmentId)
          .get();

      if (!cancelledDoc.exists) {
        if (kDebugMode) {
          print('Cancelled appointment not found');
        }
        return;
      }

      final cancelledData = cancelledDoc.data()!;
      final availableDate = cancelledData['date'] as String;
      final availableTime = cancelledData['time'] as String;
      final hospital = cancelledData['hospital'] as String? ?? '';
      final operationType = cancelledData['operationType'] as String? ?? '';

      // Get all patients scheduled after the cancelled appointment
      final eligiblePatients =
          await getPatientsAfterAppointment(cancelledAppointmentId);

      if (eligiblePatients.isEmpty) {
        if (kDebugMode) {
          print('No eligible patients found for slot cancellation');
        }
        return;
      }

      // Send slot available notification to all eligible patients
      await sendSlotAvailableNotification(
        availableDate: availableDate,
        availableTime: availableTime,
        hospital: hospital,
        operationType: operationType,
        eligiblePatients: eligiblePatients,
        context: context,
      );

      if (kDebugMode) {
        print(
            'Slot cancellation handled: Notified ${eligiblePatients.length} patients');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling slot cancellation: $e');
      }
    }
  }
}

