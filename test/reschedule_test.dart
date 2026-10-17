import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_appointment/services/slot_lock_service.dart';
import 'package:my_appointment/view/patient-views/dialog_screen.dart';

class FakeUser implements User {
  @override
  final String uid;
  @override
  final String? email;
  FakeUser(this.uid, this.email);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeFirebaseFirestore db;
  final user = FakeUser('p1', 'p1@example.com');

  Map<String, dynamic> appt(String patientId, String date, String time,
          {String status = 'active'}) =>
      {
        'patientID': patientId,
        'email': '$patientId@example.com',
        'name': 'Patient $patientId',
        'date': date,
        'time': time,
        'status': status,
        'hospital': 'General',
        'initialReminderSent': true,
      };

  UpdateAppointmentScreen screen(String currentId, String date) =>
      UpdateAppointmentScreen(
        currentAppointmentId: currentId,
        selectedAvailableDate: date,
        user: user,
        firestore: db,
      );

  setUp(() {
    db = FakeFirebaseFirestore();
    SlotLockService.debugFirestore = db;
  });
  tearDown(() => SlotLockService.debugFirestore = null);

  test('moves the appointment to the freed slot in one step', () async {
    await db.collection('Appointments').doc('mine').set(appt('p1', '20-12-2025', '02:00 PM'));
    await db.collection('Appointments').doc('freed')
        .set(appt('p2', '10-12-2025', '10:00 AM', status: 'cancelled'));

    await screen('mine', '10-12-2025').updateAppointment();

    final mine = await db.collection('Appointments').doc('mine').get();
    expect(mine['status'], 'cancelled');

    final all = await db.collection('Appointments').get();
    final created = all.docs.where((d) => d.id != 'mine' && d.id != 'freed').single;
    expect(created['date'], '10-12-2025');
    expect(created['time'], '10:00 AM');
    expect(created['status'], 'active');
    expect(created['patientID'], 'p1');
    expect(created['originalDate'], '20-12-2025');
    expect(created['daysMoved'], 10);
    expect(created.data().containsKey('initialReminderSent'), isFalse);

    final lock = await SlotLockService.lockRef('10-12-2025', '10:00 AM').get();
    expect(lock['appointmentId'], created.id);
  });

  test('keeps the current appointment if no freed slot is left', () async {
    await db.collection('Appointments').doc('mine').set(appt('p1', '20-12-2025', '02:00 PM'));
    await db.collection('Appointments').doc('freed')
        .set(appt('p2', '10-12-2025', '10:00 AM', status: 'cancelled'));
    // Someone already re-booked that time
    await db.collection('Appointments').doc('other').set(appt('p3', '10-12-2025', '10:00 AM'));

    await expectLater(screen('mine', '10-12-2025').updateAppointment(), throwsException);

    final mine = await db.collection('Appointments').doc('mine').get();
    expect(mine['status'], 'active');
    expect((await db.collection('Appointments').get()).size, 3);
  });

  test('refuses someone else\'s appointment', () async {
    await db.collection('Appointments').doc('theirs').set(appt('p9', '20-12-2025', '02:00 PM'));
    await expectLater(screen('theirs', '10-12-2025').updateAppointment(), throwsException);
  });
}
