import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_metrics_service.dart';
import '../utils/appointment_status.dart';

/// Firestore and Cloud Functions access for the web dashboard.
/// Provided at the app root (see main.dart); widgets get it with
/// `context.read<DashboardRepository>()`.
class DashboardRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final DashboardMetricsService _metricsService = DashboardMetricsService();

  DashboardRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  // ---------------------------------------------------------------------------
  // Appointment streams
  // ---------------------------------------------------------------------------

  /// Stream of appointments from today to next 30 days
  /// Note: We fetch all appointments with status filter, then filter by date in memory
  /// to avoid Firestore's disjunction limit (max 30 disjunctions)
  /// Includes 'AVAILABLE' status to show cancelled appointments that are set to AVAILABLE for reallocation
  Stream<QuerySnapshot> watchDashboardAppointments() {
    return _db
        .collection('Appointments')
        .where('status', whereIn: <String>{
      'active',
      'cancelled',
      'AVAILABLE', // Include AVAILABLE status (cancelled appointments set to AVAILABLE for reallocation)
      'ON_HOLD_OFFER_SENT', // Include ON_HOLD_OFFER_SENT status (slot offer sent, awaiting reply)
      'no response',
      'REMINDER_SENT_AWAITING_REPLY', // Include reminder sent status
      'CONFIRMED', // Include confirmed status
      // Spellings written elsewhere that were previously missing here, e.g.
      // Cloud Functions write 'reminder_sent_awaiting_reply' (lowercase) and
      // 'Confirmed_Priority' for patients still holding their slot
      ...AppointmentStatus.bookedValues,
      ...AppointmentStatus.cancelledValues,
    }.toList()).snapshots();
  }

  /// Priority Queue: patients on the priority list.
  /// Note: 'date' is a 'dd-MM-yyyy' string, so this orderBy is NOT
  /// chronological (it is kept because it matches the composite index);
  /// consumers sort by AppointmentData.appointmentDateTime (see
  /// PriorityQueueCard).
  Stream<QuerySnapshot> watchPriorityQueue() {
    return _db
        .collection('Appointments')
        .where('isPriority', isEqualTo: true)
        .where('status', isEqualTo: 'Confirmed_Priority')
        .orderBy('date')
        .snapshots();
  }

  /// Every appointment (used to compute the KPI cards in real time).
  Stream<QuerySnapshot> watchAllAppointments() {
    return _db.collection('Appointments').snapshots();
  }

  /// Most recent appointment for [patientId] on [date] ('dd-MM-yyyy').
  Future<QuerySnapshot<Map<String, dynamic>>> getAppointmentByPatientAndDate(
      String patientId, String date) {
    return _db
        .collection('Appointments')
        .where('patientID', isEqualTo: patientId)
        .where('date', isEqualTo: date)
        .limit(1)
        .get();
  }

  /// Admin edit of an appointment (EditAppointmentDialog).
  Future<void> updateAppointmentDetails({
    required String documentId,
    required String name,
    required String phone,
    required String date,
    required String time,
  }) {
    return _db.collection('Appointments').doc(documentId).update({
      'name': name,
      'phone': phone,
      'date': date,
      'time': time,
      'lastUpdated': FieldValue.serverTimestamp(),
      'updatedBy': 'admin',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // CSV import (batched writes)
  // ---------------------------------------------------------------------------

  WriteBatch newBatch() => _db.batch();

  /// Adds Appointments/[docId] = [data] to [batch] (full overwrite, no merge).
  void setAppointmentInBatch(
      WriteBatch batch, String docId, Map<String, dynamic> data) {
    // Use set with merge: false to ensure all fields are set
    batch.set(_db.collection('Appointments').doc(docId), data,
        SetOptions(merge: false));
  }

  Future<void> commitBatch(WriteBatch batch) => batch.commit();

  Future<DocumentSnapshot<Map<String, dynamic>>> getAppointmentDoc(
      String docId) {
    return _db.collection('Appointments').doc(docId).get();
  }

  // ---------------------------------------------------------------------------
  // Activity log (DashboardMetrics/metrics/activityLog)
  // ---------------------------------------------------------------------------

  /// Activity-log types shown under each filter chip, where a chip covers
  /// more than one stored type. 'slot_offer' entries (written by the
  /// slot-offer Cloud Function) belong with the cascades.
  static const Map<String, List<String>> activityLogTypeGroups = {
    'cascade_trigger': ['cascade_trigger', 'slot_offer'],
  };

  /// See [DashboardMetricsService.getActivityLogStream].
  Stream<QuerySnapshot> watchActivityLog({
    int limit = 10,
    String? typeFilter,
  }) {
    return _metricsService.getActivityLogStream(
      limit: limit,
      typeFilter: typeFilter,
      typeFilters: activityLogTypeGroups[typeFilter],
    );
  }

  Future<void> addActivityLogEntry({
    required String message,
    required String type,
  }) async {
    await _db
        .collection('DashboardMetrics')
        .doc('metrics')
        .collection('activityLog')
        .add({
      'message': message,
      'timestamp': Timestamp.now(),
      'type': type,
    });
  }

  // ---------------------------------------------------------------------------
  // Reallocation chart
  // ---------------------------------------------------------------------------

  /// Fetch reallocation data from Firestore for the last 7 days.
  /// Returns counts per calendar day (today and the 6 days before it),
  /// ordered oldest -> today; see [groupReallocationsByDay] for the keys.
  /// A reallocation's day is its updatedAt (when it happened), else createdAt.
  Future<Map<String, int>> fetchWeeklyReallocationCounts() async {
    // Query appointments with reallocationStatus == 'Reallocated'
    final querySnapshot = await _db
        .collection('Appointments')
        .where('reallocationStatus', isEqualTo: 'Reallocated')
        .get();

    final dates = <DateTime>[];
    for (var doc in querySnapshot.docs) {
      final data = doc.data();
      final createdAt = data['createdAt'];
      final updatedAt = data['updatedAt'];

      // Use updatedAt if available (when reallocation happened), otherwise createdAt
      if (updatedAt is Timestamp) {
        dates.add(updatedAt.toDate());
      } else if (createdAt is Timestamp) {
        dates.add(createdAt.toDate());
      }
    }

    return groupReallocationsByDay(dates, DateTime.now());
  }

  /// Counts [dates] per calendar day for the 7 days ending today ([now]'s
  /// date), oldest first. Keys are 'EEE dd/MM' (e.g. 'Sat 17/10'), unique
  /// because the 7 days have 7 different weekdays. Dates outside the window
  /// are ignored.
  static Map<String, int> groupReallocationsByDay(
      Iterable<DateTime> dates, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final days = List<DateTime>.generate(
        7, (i) => DateTime(today.year, today.month, today.day - (6 - i)));
    final labelFormat = DateFormat('EEE dd/MM');

    final counts = <String, int>{
      for (final day in days) labelFormat.format(day): 0,
    };
    for (final date in dates) {
      final day = DateTime(date.year, date.month, date.day);
      if (day.isBefore(days.first) || day.isAfter(today)) continue;
      final key = labelFormat.format(day);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  // ---------------------------------------------------------------------------
  // Cloud Functions (SMS)
  // ---------------------------------------------------------------------------

  /// Callable `sendCustomSms` (custom message text).
  Future<HttpsCallableResult> sendCustomSms({
    required String phone,
    required String message,
  }) {
    return _functions.httpsCallable('sendCustomSms').call({
      'phone': phone,
      'message': message,
    });
  }

  /// Callable `sendSmsReminder` (standard reminder message).
  Future<HttpsCallableResult> sendSmsReminder({
    required String patientPhone,
    required String slotStatus,
    required String patientId,
    required String appointmentDate,
    required String appointmentTime,
  }) {
    return _functions.httpsCallable('sendSmsReminder').call({
      'patientPhone': patientPhone,
      'slotStatus': slotStatus,
      'patientId': patientId,
      'appointmentDate': appointmentDate,
      'appointmentTime': appointmentTime,
    });
  }
}
