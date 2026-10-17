import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_appointment/services/appointment_service.dart';
import 'package:my_appointment/services/slot_lock_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late AppointmentService service;

  Future<void> addAppointment(String id, Map<String, dynamic> data) =>
      db.collection('Appointments').doc(id).set(data);

  Map<String, dynamic> appointment(String patientId, String date, String time,
          {String status = 'active'}) =>
      {
        'patientID': patientId,
        'email': '$patientId@example.com',
        'name': 'Patient $patientId',
        'date': date,
        'time': time,
        'status': status,
        'hospital': 'General',
        'operationType': 'Checkup',
      };

  /// A BuildContext for claimSlot (only passed through to notifications).
  Future<BuildContext> contextFor(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(Builder(builder: (context) {
      captured = context;
      return const SizedBox();
    }));
    return captured;
  }

  /// claimSlot's result, or the error it threw (runAsync would swallow it).
  Future<Object> claimOutcome(WidgetTester tester, String patientId, String oldId,
      {String date = '10-12-2025', String time = '10:00 AM'}) async {
    final context = await contextFor(tester);
    final outcome = await tester.runAsync<Object>(() async {
      try {
        return await service.claimSlot(
          patientId: patientId,
          newDate: date,
          newTime: time,
          newHospital: 'General',
          newOperationType: 'Checkup',
          oldAppointmentDocumentId: oldId,
          context: context,
        );
      } catch (e) {
        return e;
      }
    });
    return outcome!;
  }

  Future<bool> claim(WidgetTester tester, String patientId, String oldId) async =>
      await claimOutcome(tester, patientId, oldId) as bool;

  bool isSlotTaken(Object outcome) =>
      outcome is! bool && outcome.toString().contains('SLOT_ALREADY_TAKEN');

  setUp(() {
    db = FakeFirebaseFirestore();
    SlotLockService.debugFirestore = db;
    service = AppointmentService(firestore: db);
  });

  tearDown(() => SlotLockService.debugFirestore = null);

  testWidgets('claims a free slot: new appointment, lock, old marked reallocated',
      (tester) async {
    await addAppointment('old', appointment('p1', '20-12-2025', '02:00 PM'));

    expect(await claim(tester, 'p1', 'old'), isTrue);

    final all = await tester.runAsync(() => db.collection('Appointments').get());
    final created = all!.docs.where((d) => d.id != 'old').single;
    expect(created['date'], '10-12-2025');
    expect(created['time'], '10:00 AM');
    expect(created['status'], 'active');
    expect(created['patientID'], 'p1');

    final old = await tester.runAsync(() => db.collection('Appointments').doc('old').get());
    expect(old!['reallocationStatus'], 'Reallocated');
    expect(old['daysMoved'], 10);

    final lock = await tester.runAsync(
        () => SlotLockService.lockRef('10-12-2025', '10:00 AM').get());
    expect(lock!.data()!['appointmentId'], created.id);
  });

  testWidgets('a confirmed (not just "active") appointment can claim', (tester) async {
    await addAppointment(
        'old', appointment('p1', '20-12-2025', '02:00 PM', status: 'CONFIRMED'));
    expect(await claim(tester, 'p1', 'old'), isTrue);
  });

  testWidgets('slot held by an existing booked appointment throws SLOT_ALREADY_TAKEN',
      (tester) async {
    await addAppointment('old', appointment('p1', '20-12-2025', '02:00 PM'));
    // Stored in 24-hour form: still the same slot as '10:00 AM'
    await addAppointment('other', appointment('p2', '10-12-2025', '10:00'));

    expect(isSlotTaken(await claimOutcome(tester, 'p1', 'old')), isTrue);
  });

  testWidgets('second patient claiming the same slot is rejected', (tester) async {
    await addAppointment('a', appointment('p1', '20-12-2025', '02:00 PM'));
    await addAppointment('b', appointment('p2', '21-12-2025', '03:00 PM'));

    expect(await claim(tester, 'p1', 'a'), isTrue);
    expect(isSlotTaken(await claimOutcome(tester, 'p2', 'b')), isTrue);
  });

  testWidgets('lock held by a cancelled appointment no longer blocks the slot',
      (tester) async {
    await addAppointment('old', appointment('p1', '20-12-2025', '02:00 PM'));
    await addAppointment(
        'gone', appointment('p2', '10-12-2025', '10:00 AM', status: 'cancelled'));
    await tester.runAsync(() => SlotLockService.lockRef('10-12-2025', '10:00 AM')
        .set({'appointmentId': 'gone'}));

    expect(await claim(tester, 'p1', 'old'), isTrue);
  });

  testWidgets('cannot claim with a cancelled or someone else\'s appointment',
      (tester) async {
    await addAppointment(
        'cancelled', appointment('p1', '20-12-2025', '02:00 PM', status: 'cancelled'));
    await addAppointment('theirs', appointment('p2', '21-12-2025', '02:00 PM'));

    expect(await claim(tester, 'p1', 'cancelled'), isFalse);
    expect(await claim(tester, 'p1', 'theirs'), isFalse);
    expect(await claim(tester, 'p1', 'missing'), isFalse);
  });

  testWidgets('claiming keeps the old slot held (it is not offered to others)',
      (tester) async {
    await addAppointment('old', appointment('p1', '20-12-2025', '02:00 PM'));
    await addAppointment('b', appointment('p2', '22-12-2025', '09:00 AM'));

    expect(await claim(tester, 'p1', 'old'), isTrue);

    // p1 still holds 20-12 02:00 PM, so p2 can't take it
    final outcome = await claimOutcome(tester, 'p2', 'b',
        date: '20-12-2025', time: '02:00 PM');
    expect(isSlotTaken(outcome), isTrue);
  });
}
