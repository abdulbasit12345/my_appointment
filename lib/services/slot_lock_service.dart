import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../utils/appointment_status.dart';
import '../utils/date_utils.dart';

/// Prevents two bookings for the same date + time.
///
/// Firestore transactions can't run queries, so each booked slot also gets a
/// `SlotLocks/{date_HH:mm}` document naming the appointment that holds it.
/// Reading and writing that document inside the booking transaction makes
/// concurrent bookings conflict: one commits, the other retries and sees the
/// lock. A lock only counts while its appointment is still booked at that
/// date/time, so cancelling or moving an appointment frees the slot.
///
/// Appointments created before locks existed (or by writers that don't use
/// them, e.g. CSV import) are covered by [isSlotTakenByQuery].
class SlotLockService {
  static const String collection = 'SlotLocks';

  /// Replaced with a fake Firestore in tests.
  @visibleForTesting
  static FirebaseFirestore? debugFirestore;

  static FirebaseFirestore get _db =>
      debugFirestore ?? FirebaseFirestore.instance;

  /// Same id for '02:00 PM' and '14:00'.
  static String lockId(String date, String time) {
    final parsed = Date_Utils.tryParseTimeFlexible(time);
    final normalizedTime = parsed != null
        ? DateFormat('HH:mm').format(parsed)
        : time.trim().replaceAll(' ', '');
    return '${date.trim()}_$normalizedTime'.replaceAll('/', '-');
  }

  static DocumentReference<Map<String, dynamic>> lockRef(
          String date, String time) =>
      _db.collection(collection).doc(lockId(date, time));

  /// Spellings the same time may be stored under ('02:00 PM', '2:00 PM', '14:00').
  static List<String> timeVariants(String time) {
    final variants = <String>{time.trim()};
    final parsed = Date_Utils.tryParseTimeFlexible(time);
    if (parsed != null) {
      variants.add(DateFormat('hh:mm a').format(parsed));
      variants.add(DateFormat('h:mm a').format(parsed));
      variants.add(DateFormat('HH:mm').format(parsed));
    }
    return variants.toList();
  }

  /// Non-transactional check against existing appointments.
  static Future<bool> isSlotTakenByQuery(
    String date,
    String time, {
    String? ignoreAppointmentId,
  }) async {
    final snapshot = await _db
        .collection('Appointments')
        .where('date', isEqualTo: date)
        .where('time', whereIn: timeVariants(time))
        .get();

    return snapshot.docs.any((doc) =>
        doc.id != ignoreAppointmentId &&
        AppointmentStatus.isBooked(doc.data()['status'] as String?));
  }

  /// Must be called before any write in [transaction].
  static Future<bool> isLockedInTransaction(
    Transaction transaction,
    String date,
    String time, {
    String? ignoreAppointmentId,
  }) async {
    final lockDoc = await transaction.get(lockRef(date, time));
    if (!lockDoc.exists) return false;

    final holderId = lockDoc.data()?['appointmentId'] as String?;
    if (holderId == null ||
        holderId.isEmpty ||
        holderId == ignoreAppointmentId) {
      return false;
    }

    final holderDoc =
        await transaction.get(_db.collection('Appointments').doc(holderId));
    if (!holderDoc.exists) return false;

    final holder = holderDoc.data()!;
    final stillBooked =
        AppointmentStatus.isBooked(holder['status'] as String?);
    final sameSlot = lockId(holder['date'] as String? ?? '',
            holder['time'] as String? ?? '') ==
        lockId(date, time);
    return stillBooked && sameSlot;
  }

  static void writeLock(
    Transaction transaction,
    String date,
    String time,
    String appointmentId,
  ) {
    transaction.set(lockRef(date, time), {
      'appointmentId': appointmentId,
      'date': date,
      'time': time,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
