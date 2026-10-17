import 'package:flutter_test/flutter_test.dart';
import 'package:my_appointment/services/slot_lock_service.dart';
import 'package:my_appointment/utils/appointment_status.dart';
import 'package:my_appointment/utils/date_utils.dart';

void main() {
  group('Date_Utils.tryParseTimeFlexible', () {
    test('keeps PM (previously parsed as AM)', () {
      final t = Date_Utils.tryParseTimeFlexible('02:00 PM')!;
      expect([t.hour, t.minute], [14, 0]);
    });

    test('handles 12 AM / 12 PM', () {
      expect(Date_Utils.tryParseTimeFlexible('12:30 AM')!.hour, 0);
      expect(Date_Utils.tryParseTimeFlexible('12:30 PM')!.hour, 12);
    });

    test('accepts 24-hour, lowercase and no-space forms', () {
      expect(Date_Utils.tryParseTimeFlexible('14:05')!.hour, 14);
      expect(Date_Utils.tryParseTimeFlexible('2:00 pm')!.hour, 14);
      expect(Date_Utils.tryParseTimeFlexible('02:00PM')!.hour, 14);
    });

    test('accepts seconds (Excel CSV) and ignores them', () {
      final t = Date_Utils.tryParseTimeFlexible('14:30:00')!;
      expect([t.hour, t.minute], [14, 30]);
      expect(Date_Utils.tryParseTimeFlexible('02:30:15 PM')!.hour, 14);
      expect(Date_Utils.tryParseTimeFlexible('14:30:99'), isNull);
    });

    test('rejects invalid times', () {
      for (final s in ['', 'abc', '25:00', '10:75', '13:00 PM', '0:30 AM']) {
        expect(Date_Utils.tryParseTimeFlexible(s), isNull, reason: s);
      }
    });
  });

  group('Date_Utils.tryParseDateStrict', () {
    test('parses dd-MM-yyyy', () {
      expect(Date_Utils.tryParseDateStrict('12-12-2025'), DateTime(2025, 12, 12));
      expect(Date_Utils.tryParseDateStrict('5-1-2025'), DateTime(2025, 1, 5));
    });

    test('rejects values the lenient parser rolled over', () {
      expect(Date_Utils.tryParseDateStrict('32-01-2025'), isNull);
      expect(Date_Utils.tryParseDateStrict('2025-12-12'), isNull);
      expect(Date_Utils.tryParseDateStrict(''), isNull);
      expect(Date_Utils.tryParseDateStrict(null), isNull);
    });
  });

  group('AppointmentStatus', () {
    test('booked covers every spelling in use', () {
      for (final s in [
        'active',
        'ACTIVE',
        'BOOKED',
        'CONFIRMED',
        'Confirmed_Priority',
        'reminder_sent_awaiting_reply',
        'REMINDER_SENT_AWAITING_REPLY',
        'no response',
      ]) {
        expect(AppointmentStatus.isBooked(s), isTrue, reason: s);
        expect(AppointmentStatus.isCancelled(s), isFalse, reason: s);
      }
    });

    test('cancelled spellings', () {
      for (final s in ['cancelled', 'CANCELLED', 'Cancelled', 'canceled']) {
        expect(AppointmentStatus.isCancelled(s), isTrue, reason: s);
        expect(AppointmentStatus.isBooked(s), isFalse, reason: s);
      }
      expect(AppointmentStatus.isBooked(null), isFalse);
    });

    test('lists fit in a Firestore whereIn', () {
      expect(AppointmentStatus.bookedValues.length, lessThanOrEqualTo(30));
    });
  });

  group('SlotLockService', () {
    test('same slot gets the same lock id in 12h and 24h form', () {
      expect(SlotLockService.lockId('12-12-2025', '02:00 PM'),
          SlotLockService.lockId('12-12-2025', '14:00'));
      expect(SlotLockService.lockId('12-12-2025', '02:00 PM'),
          isNot(SlotLockService.lockId('12-12-2025', '02:00 AM')));
    });

    test('time variants include stored spellings', () {
      expect(SlotLockService.timeVariants('02:00 PM'),
          containsAll(['02:00 PM', '2:00 PM', '14:00']));
    });
  });
}
