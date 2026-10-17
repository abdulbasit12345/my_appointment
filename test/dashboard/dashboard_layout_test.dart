import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:my_appointment/repositories/dashboard_repository.dart';
import 'package:my_appointment/view/dashboard/dashboard_screen.dart';
import 'package:provider/provider.dart';

/// Serves the dashboard streams from fixed snapshots and counts how often
/// each stream is requested.
class _FakeDashboardRepository implements DashboardRepository {
  final QuerySnapshot appointments;
  final QuerySnapshot empty;
  final Map<String, int> calls = {};

  _FakeDashboardRepository(this.appointments, this.empty);

  Stream<QuerySnapshot> _stream(String name, QuerySnapshot snap) {
    calls[name] = (calls[name] ?? 0) + 1;
    // A stream that emits once and stays open, like Firestore's snapshots().
    final controller = StreamController<QuerySnapshot>();
    controller.add(snap);
    return controller.stream;
  }

  @override
  Stream<QuerySnapshot> watchDashboardAppointments() =>
      _stream('appointments', appointments);

  @override
  Stream<QuerySnapshot> watchPriorityQueue() => _stream('priority', empty);

  @override
  Stream<QuerySnapshot> watchAllAppointments() =>
      _stream('all', appointments);

  @override
  Stream<QuerySnapshot> watchActivityLog({int limit = 10, String? typeFilter}) =>
      _stream('activity', empty);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeDashboardRepository> _repoWithAppointments(
    WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final db = FakeFirebaseFirestore();
    final fmt = DateFormat('dd-MM-yyyy');
    final now = DateTime.now();
    for (var i = 0; i < 8; i++) {
      await db.collection('Appointments').add({
        'patientID': 'p$i',
        'name': 'Patient $i',
        'phone': '+92300123456$i',
        'email': '',
        'address': '',
        'hospital': '',
        'status': 'active',
        'date': fmt.format(now.add(Duration(days: i))),
        'time': '10:00',
      });
    }
    final appointments = await db.collection('Appointments').get();
    final empty = await db.collection('Nothing').get();
    return _FakeDashboardRepository(appointments, empty);
  }))!;
}

/// Layout errors other than RenderFlex overflows. Overflows are ignored:
/// the test font's glyphs are much wider than real fonts, so text rows
/// overflow in tests where they don't in the app.
final List<FlutterErrorDetails> _layoutErrors = [];

Future<void> _pumpDashboard(
    WidgetTester tester, DashboardRepository repo, Size size) async {
  _layoutErrors.clear();
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    _layoutErrors.add(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Provider<DashboardRepository>.value(
      value: repo,
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 2)); // KPI count-up animation
}

void main() {
  testWidgets('stacked layout (700px) renders appointments without errors',
      (tester) async {
    final repo = await _repoWithAppointments(tester);
    await _pumpDashboard(tester, repo, const Size(700, 1400));

    expect(_layoutErrors.map((e) => e.exceptionAsString()), isEmpty);
    expect(find.text('Patient 0'), findsOneWidget);
    expect(find.text('Reallocation Command Center'), findsOneWidget);
  });

  testWidgets('wide layout (1400px) still renders', (tester) async {
    final repo = await _repoWithAppointments(tester);
    await _pumpDashboard(tester, repo, const Size(1400, 1000));

    expect(_layoutErrors.map((e) => e.exceptionAsString()), isEmpty);
    expect(find.text('Patient 0'), findsOneWidget);
  });

  testWidgets('typing in search does not resubscribe to Firestore streams',
      (tester) async {
    final repo = await _repoWithAppointments(tester);
    await _pumpDashboard(tester, repo, const Size(1400, 1000));
    final before = Map<String, int>.from(repo.calls);

    await tester.enterText(find.byType(TextField).first, 'Patient 1');
    await tester.pump();

    expect(_layoutErrors.map((e) => e.exceptionAsString()), isEmpty);
    expect(repo.calls, before);
    expect(find.text('Patient 1'), findsWidgets);
    expect(find.text('Patient 2'), findsNothing);
  });
}
