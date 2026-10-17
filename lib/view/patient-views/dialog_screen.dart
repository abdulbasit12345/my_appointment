import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_appointment/res/color.dart';
import 'package:my_appointment/services/slot_lock_service.dart';
import 'package:my_appointment/utils/appointment_status.dart';
import 'package:my_appointment/utils/date_utils.dart';
import 'package:my_appointment/view/patient-views/patientHomeViewNew.dart';

class DialogScreen extends StatefulWidget {
  const DialogScreen({super.key});

  @override
  State<DialogScreen> createState() => _DialogScreenState();
}

class _DialogScreenState extends State<DialogScreen> {
  // Change the date format
  final DateFormat dateFormat = DateFormat('dd-MM-yyyy');

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}

class UpdateAppointmentScreen extends StatelessWidget {
  final String currentAppointmentId;
  final String selectedAvailableDate;
  final User? user;

  /// Defaults to FirebaseFirestore.instance; replaced in tests.
  final FirebaseFirestore? firestore;

  UpdateAppointmentScreen(
      {super.key,
      required this.currentAppointmentId,
      required this.selectedAvailableDate,
      required this.user,
      this.firestore});

  // Change the date format to dd-MM-yyyy
  final DateFormat dateFormat = DateFormat('dd-MM-yyyy');

  /// Moves the current appointment to a freed slot on [selectedAvailableDate].
  ///
  /// The freed slot is a cancelled appointment on that date whose time isn't
  /// booked again. In one transaction: the new appointment is created, the
  /// current one is cancelled (the onAppointmentWritten Cloud Function then
  /// offers it to others) and the slot is locked. Nothing changes if any
  /// step fails. (Previously the current appointment was cancelled first and
  /// the second step always failed, leaving the patient with no appointment.)
  Future<void> updateAppointment() async {
    final db = firestore ?? FirebaseFirestore.instance;
    final currentRef = db.collection('Appointments').doc(currentAppointmentId);
    final current = await currentRef.get();
    final currentData = current.data();
    if (currentData == null ||
        currentData['patientID'] != user?.uid ||
        !AppointmentStatus.isBooked(currentData['status'] as String?)) {
      throw Exception('This appointment can no longer be rescheduled.');
    }

    // Find a freed (cancelled) slot on the chosen date that is still free
    final freed = await db
        .collection('Appointments')
        .where('date', isEqualTo: selectedAvailableDate)
        .where('status', whereIn: AppointmentStatus.cancelledValues)
        .get();
    String? newTime;
    for (final doc in freed.docs) {
      final time = doc.data()['time'];
      if (time is! String || time.isEmpty) continue;
      if (!await SlotLockService.isSlotTakenByQuery(selectedAvailableDate, time,
          ignoreAppointmentId: currentAppointmentId)) {
        newTime = time;
        break;
      }
    }
    if (newTime == null) {
      throw Exception('That date is no longer available.');
    }
    final time = newTime;

    final oldDate = currentData['date'] as String? ?? '';
    final oldTime = currentData['time'] as String? ?? '';
    final oldParsed = Date_Utils.tryParseDateStrict(oldDate);
    final newParsed = Date_Utils.tryParseDateStrict(selectedAvailableDate);
    final daysMoved = oldParsed != null &&
            newParsed != null &&
            newParsed.isBefore(oldParsed)
        ? oldParsed.difference(newParsed).inDays
        : 0;

    final newRef = db.collection('Appointments').doc(
        '${user?.uid}-${selectedAvailableDate.replaceAll('-', '')}-${time.replaceAll(':', '-').replaceAll(' ', '-')}-${DateTime.now().millisecondsSinceEpoch}');

    final moved = await db.runTransaction<bool>((transaction) async {
      if (await SlotLockService.isLockedInTransaction(
          transaction, selectedAvailableDate, time,
          ignoreAppointmentId: currentAppointmentId)) {
        return false;
      }
      final fresh = await transaction.get(currentRef);
      if (!AppointmentStatus.isBooked(fresh.data()?['status'] as String?)) {
        return false;
      }
      transaction.set(newRef, {
        ...currentData,
        'date': selectedAvailableDate,
        'time': time,
        'email': user?.email ?? currentData['email'],
        'status': AppointmentStatus.active,
        'reallocationStatus': 'Reallocated',
        'originalDate': oldDate,
        'originalTime': oldTime,
        'daysMoved': daysMoved,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }
        // Per-appointment state that must not carry over to the new date
        // (e.g. the 48-hour reminder must be sent again)
        ..remove('appointmentAt')
        ..remove('lastSlotOfferEventId')
        ..remove('initialReminderSent')
        ..remove('lastReminderSent')
        ..remove('userResponse'));
      transaction.update(currentRef, {
        'status': AppointmentStatus.cancelled,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      SlotLockService.writeLock(
          transaction, selectedAvailableDate, time, newRef.id);
      return true;
    });
    if (!moved) {
      throw Exception('That slot was just taken. Please choose another date.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Appointment'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current Appointment ID: $currentAppointmentId',
                style: TextStyle(
                  color: AppColors.blackColor,
                )),
            Text('New Appointment Date: $selectedAvailableDate',
                style: TextStyle(
                  color: AppColors.blackColor,
                )),
            ElevatedButton(
              onPressed: () async {
                try {
                  await updateAppointment();
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        e.toString().replaceFirst('Exception: ', '')),
                    backgroundColor: Colors.red,
                  ));
                  return;
                }
                if (!context.mounted) return;
                Navigator.of(context).pushReplacement(CupertinoPageRoute(
                    builder: (context) => const PatientHomeViewNew()));
              },
              child: const Text('Confirm Update',
                  style: TextStyle(
                    color: AppColors.blackColor,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
