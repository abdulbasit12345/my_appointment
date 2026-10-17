import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_appointment/view/forget_password.dart';

void main() {
  testWidgets('Forget password screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ForgetPasswordView()));

    expect(find.text('Reset your password.'), findsOneWidget);
    expect(find.text('Send Reset Link'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });
}
