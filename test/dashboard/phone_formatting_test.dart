import 'package:flutter_test/flutter_test.dart';
import 'package:my_appointment/view/dashboard/services/phone_formatting.dart';

void main() {
  group('formatPhoneToE164', () {
    final cases = <String, String>{
      // already international
      '+923001234567': '+923001234567',
      '+92 300-123 4567': '+923001234567',
      '+44 7700 900123': '+447700900123',
      // 00 prefix
      '00923001234567': '+923001234567',
      '00447700900123': '+447700900123',
      // local mobiles with leading 0
      '03001234567': '+923001234567',
      '0300-1234567': '+923001234567',
      '07700900123': '+447700900123',
      '07700 900 123': '+447700900123',
      '02079460000': '+442079460000', // UK landline (11 digits, 0)
      // country code without +
      '923001234567': '+923001234567',
      '447700900123': '+447700900123',
      // mobiles without 0 or country code
      '3001234567': '+923001234567',
      '7700900123': '+447700900123',
      // fallbacks kept from the original function
      '2125551234': '+12125551234', // 10 digits -> US
      '12125551234': '+12125551234', // 11 digits starting with 1 -> US
      '93123456789': '+93123456789', // was '+9293123456789'
      '020123456789': '+4420123456789', // 0 + more than 11 digits -> UK
      '': '',
    };
    cases.forEach((input, expected) {
      test('"$input" -> "$expected"', () {
        expect(formatPhoneToE164(input), expected);
      });
    });

    test('Excel scientific notation is expanded first', () {
      expect(formatPhoneToE164('9.23001234567E+11'), '+923001234567');
    });
  });
}
