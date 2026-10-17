import 'package:flutter_test/flutter_test.dart';
import 'package:my_appointment/models/appointment_data.dart';
import 'package:my_appointment/repositories/dashboard_repository.dart';
import 'package:my_appointment/view/dashboard/appointment_filters.dart';
import 'package:my_appointment/view/dashboard/reallocation_chart_dialog.dart';
import 'package:my_appointment/view/dashboard/widgets/reminder_button_style.dart';

AppointmentData appt(String status, {DateTime? date, String? userResponse}) =>
    AppointmentData(
      documentId: 'd',
      patientID: 'p',
      name: 'Pat',
      phone: '+923001234567',
      email: '',
      address: '',
      hospital: '',
      status: status,
      date: date ?? DateTime.now(),
      time: DateTime(2000, 1, 1, 10),
      userResponse: userResponse,
    );

void main() {
  group('reminder / quick-action buttons', () {
    test('disabled for cancelled and available slots', () {
      for (final s in ['cancelled', 'CANCELLED', 'canceled', 'AVAILABLE', 'available']) {
        expect(isReminderButtonEnabled(appt(s)), isFalse, reason: s);
        expect(isQuickActionsEnabled(appt(s)), isFalse, reason: s);
      }
    });

    test('awaitingReply behaves like reminder_sent_awaiting_reply', () {
      for (final s in ['awaitingReply', 'reminder_sent_awaiting_reply', 'REMINDER_SENT_AWAITING_REPLY']) {
        expect(reminderButtonText(appt(s)), 'Reminder Sent', reason: s);
        expect(isReminderButtonEnabled(appt(s)), isFalse, reason: s);
        expect(isQuickActionsEnabled(appt(s)), isTrue, reason: s);
      }
    });

    test('booked statuses stay enabled', () {
      for (final s in ['active', 'CONFIRMED', 'Confirmed_Priority', 'no response']) {
        expect(isReminderButtonEnabled(appt(s)), isTrue, reason: s);
        expect(isQuickActionsEnabled(appt(s)), isTrue, reason: s);
      }
    });
  });

  group('filterAppointmentsByDateRange', () {
    final today = DateTime.now();
    DateTime day(int offset) =>
        DateTime(today.year, today.month, today.day + offset);

    test('today .. today+30 inclusive for booked appointments', () {
      final result = filterAppointmentsByDateRange([
        appt('active', date: day(-1)),
        appt('active', date: day(0)),
        appt('active', date: day(30)),
        appt('active', date: day(31)),
      ]);
      expect(result.map((a) => a.date), [day(0), day(30)]);
    });

    test('cancelled appointments from the past 7 days stay visible', () {
      final result = filterAppointmentsByDateRange([
        appt('cancelled', date: day(-7)),
        appt('cancelled', date: day(-8)),
        appt('AVAILABLE', date: day(-3)),
      ]);
      expect(result.map((a) => a.date), [day(-7), day(-3)]);
    });
  });

  group('reallocation chart', () {
    test('groups by calendar date, oldest -> today', () {
      final now = DateTime(2026, 10, 17, 15); // a Saturday
      final counts = DashboardRepository.groupReallocationsByDay([
        DateTime(2026, 10, 17, 9), // today
        DateTime(2026, 10, 10, 9), // same weekday a week ago: excluded
        DateTime(2026, 10, 11, 23, 59), // oldest day in range
        DateTime(2026, 10, 11, 1),
        DateTime(2026, 10, 18, 1), // future: excluded
      ], now);
      expect(counts.keys.toList(), [
        'Sun 11/10',
        'Mon 12/10',
        'Tue 13/10',
        'Wed 14/10',
        'Thu 15/10',
        'Fri 16/10',
        'Sat 17/10',
      ]);
      expect(counts.values.toList(), [2, 0, 0, 0, 0, 0, 1]);
    });

    test('integer y-axis interval', () {
      expect(reallocationChartInterval(0), 1);
      expect(reallocationChartInterval(1), 1);
      expect(reallocationChartInterval(10), 1);
      expect(reallocationChartInterval(11), 2);
      expect(reallocationChartInterval(95), 10);
    });
  });
}
