import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/appointment_status.dart';

/// Firestore access for the patient home screen.
/// Provided at the app root (see main.dart); widgets get it with
/// `context.read<PatientAppointmentsRepository>()`.
class PatientAppointmentsRepository {
  final FirebaseFirestore _db;

  PatientAppointmentsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _appointments =>
      _db.collection('Appointments');

  // ---------------------------------------------------------------------------
  // Appointments: reads
  // ---------------------------------------------------------------------------

  /// Live list of the patient's booked appointments (home screen list).
  /// SECURITY: Filter by both email AND patientID to ensure patient-specific
  /// appointments. When there is no logged-in user (or no email) an empty
  /// stream is returned by querying with an impossible condition.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyBookedAppointments({
    required String? uid,
    required String? email,
  }) {
    if (uid == null || email == null) {
      return _appointments
          .where('patientID', isEqualTo: '__no_user__')
          .snapshots();
    }

    return _appointments
        .where('patientID', isEqualTo: uid) // Primary filter by patientID
        .where('email', isEqualTo: email) // Secondary filter by email
        .where('status', whereIn: AppointmentStatus.bookedValues)
        .snapshots();
  }

  /// The patient's booked appointments (one-off read). Used by the
  /// available-dates and select-appointment-to-reschedule dialogs.
  Future<QuerySnapshot<Map<String, dynamic>>> getMyBookedAppointments({
    required String uid,
    required String? email,
  }) {
    return _appointments
        .where('patientID', isEqualTo: uid)
        .where('email', isEqualTo: email)
        .where('status', whereIn: AppointmentStatus.bookedValues)
        .get();
  }

  /// Appointments checked for the startup reminder dialog / notification.
  /// Intentionally still matches only the literal 'active' status.
  Future<QuerySnapshot<Map<String, dynamic>>> getActiveAppointmentsForReminder({
    required String uid,
    required String? email,
  }) {
    return _appointments
        .where('patientID', isEqualTo: uid)
        .where('email', isEqualTo: email)
        .where('status', isEqualTo: 'active')
        .get();
  }

  /// Every booked appointment (all patients). Used by the cancel flow to
  /// find other patients to notify.
  Future<QuerySnapshot<Map<String, dynamic>>> getAllBookedAppointments() {
    return _appointments
        .where('status', whereIn: AppointmentStatus.bookedValues)
        .get();
  }

  /// Every cancelled appointment (all patients); their dates are offered as
  /// available dates.
  Future<QuerySnapshot<Map<String, dynamic>>> getCancelledAppointments() {
    return _appointments
        .where('status', whereIn: AppointmentStatus.cancelledValues)
        .get();
  }

  /// A single appointment document.
  Future<DocumentSnapshot<Map<String, dynamic>>> getAppointment(
      String documentId) {
    return _appointments.doc(documentId).get();
  }

  // ---------------------------------------------------------------------------
  // Appointments: writes
  // ---------------------------------------------------------------------------

  /// "YES" on the reminder dialog: the patient still needs the appointment.
  Future<void> confirmAppointmentFromReminder(String appointmentId) {
    return _appointments.doc(appointmentId).update({
      'status': 'active',
      'confirmed': true,
      'reminderAcknowledged': true,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  /// Sets the appointment status to 'cancelled'.
  Future<void> markAppointmentCancelled(String documentId) {
    return _appointments.doc(documentId).update({'status': 'cancelled'});
  }

  // ---------------------------------------------------------------------------
  // TokenData / AppointmentGraph
  // ---------------------------------------------------------------------------

  /// The `TokenData/{userId}` document holding a user's `deviceToken`.
  Future<DocumentSnapshot<Map<String, dynamic>>> getTokenData(String userId) {
    return _db.collection('TokenData').doc(userId).get();
  }

  /// Updates the `status` field of an `AppointmentGraph` document.
  Future<void> updateAppointmentGraphStatus(String graphDocId, String status) {
    return _db.collection('AppointmentGraph').doc(graphDocId).update({
      'status': status,
    });
  }
}
