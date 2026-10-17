import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_appointment/view/dashboard/widgets/dashboard_help_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(void Function(BuildContext) onReady) => MaterialApp(
      home: Builder(builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onReady(context));
        return const Scaffold();
      }),
    );

void main() {
  testWidgets('guide opens on the requested section and every tab renders',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host((context) =>
        showDashboardHelp(context, section: DashboardHelpSection.list)));
    await tester.pumpAndSettle();

    expect(find.text('How to use the Master Dashboard'), findsOneWidget);
    expect(find.text('Columns'), findsOneWidget);

    for (final tab in [
      'Start here',
      'Labels',
      'Row buttons',
      'Add & print',
      'Right panel',
      'Questions',
    ]) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('How to use the Master Dashboard'), findsNothing);
  });

  testWidgets('opens automatically only on the first visit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(showDashboardHelpOnFirstVisit));
    await tester.pumpAndSettle();
    expect(find.text('How to use the Master Dashboard'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    // Second visit
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(showDashboardHelpOnFirstVisit));
    await tester.pumpAndSettle();
    expect(find.text('How to use the Master Dashboard'), findsNothing);
  });
}
