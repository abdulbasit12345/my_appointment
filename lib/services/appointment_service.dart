import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/appointment_status.dart';
import '../utils/date_utils.dart';
import 'slot_lock_service.dart';

/// Service class for claiming earlier slots
class AppointmentService {
  final FirebaseFirestore _firestore;

  AppointmentService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Claim a slot: Create a NEW appointment for the claimed slot (patient will have TWO appointments)
  /// The old appointment remains booked (marked 'Reallocated'), allowing the
  /// patient to have multiple appointments; it can be cancelled separately.
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

      // Verify the appointment is still booked (any booked status spelling)
      if (!AppointmentStatus.isBooked(oldAppointmentDataBefore['status'] as String?)) {
        if (kDebugMode) {
          print('Appointment is not active: ${oldAppointmentDataBefore['status']}');
        }
        return false;
      }

      // Old slot, recorded on the old appointment below
      final oldDate = oldAppointmentDataBefore['date'] as String;
      final oldTime = oldAppointmentDataBefore['time'] as String;

      // Check if the new slot is already taken by another booked appointment
      // (excluding the old appointment). This covers appointments created
      // without a slot lock; the lock check inside the transaction below
      // covers two claims racing each other.
      final slotTaken = await SlotLockService.isSlotTakenByQuery(
        newDate,
        newTime,
        ignoreAppointmentId: oldAppointmentDocumentId,
      );

      if (slotTaken) {
        if (kDebugMode) {
          print('Slot $newDate at $newTime is already taken by another patient');
        }
        // Return a specific error that can be caught and displayed to user
        throw Exception('SLOT_ALREADY_TAKEN');
      }

      // Use a transaction to ensure atomicity and prevent race conditions
      // Create a NEW appointment for the claimed slot (patient will have TWO appointments)
      final transactionResult = await _firestore.runTransaction<String>((transaction) async {
        // Re-verify the old appointment within transaction (double-check pattern)
        final appointmentDoc = await transaction.get(
          _firestore.collection('Appointments').doc(oldAppointmentDocumentId),
        );

        if (!appointmentDoc.exists) {
          if (kDebugMode) {
            print('Transaction: Old appointment document does not exist');
          }
          return 'invalid';
        }

        final appointmentData = appointmentDoc.data()!;
        
        // Verify still belongs to patient and is booked
        if (appointmentData['patientID'] != patientId ||
            !AppointmentStatus.isBooked(appointmentData['status'] as String?)) {
          if (kDebugMode) {
            print('Transaction: Appointment validation failed - patientID: ${appointmentData['patientID']}, status: ${appointmentData['status']}');
          }
          return 'invalid';
        }

        // Atomic slot check: if another claim/booking took this slot since
        // the query above, its lock is visible here (all reads happen
        // before any write in this transaction)
        if (await SlotLockService.isLockedInTransaction(
          transaction,
          newDate,
          newTime,
          ignoreAppointmentId: oldAppointmentDocumentId,
        )) {
          return 'taken';
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

        // Hold the slot for the new appointment
        SlotLockService.writeLock(transaction, newDate, newTime, newDocId);

        if (kDebugMode) {
          print('Transaction: New appointment document set successfully');
        }

        return 'ok';
      });

      if (transactionResult == 'taken') {
        if (kDebugMode) {
          print('Transaction: Slot $newDate at $newTime was claimed by another patient');
        }
        throw Exception('SLOT_ALREADY_TAKEN');
      }

      if (transactionResult != 'ok') {
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

      // The old appointment is still booked (the patient now holds both),
      // so its slot is not offered to anyone here. If the patient later
      // cancels it, the onAppointmentWritten Cloud Function offers it.

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error claiming slot: $e');
      }
      // Let the UI show its specific "slot already taken" message
      if (e.toString().contains('SLOT_ALREADY_TAKEN')) {
        rethrow;
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
}
