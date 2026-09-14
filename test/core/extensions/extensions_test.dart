import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_pilot/core/extensions/date_time_extensions.dart';
import 'package:pocket_pilot/core/extensions/num_extensions.dart';
import 'package:pocket_pilot/core/extensions/string_extensions.dart';

void main() {
  group('NumX', () {
    test('formats currency with the right symbol', () {
      expect(1234.5.toCurrency(), r'$1,234.50');
      expect(99.0.toCurrency(currencyCode: 'EUR'), '€99.00');
      expect(5000.0.toCurrency(currencyCode: 'MMK'), 'K5,000.00');
      expect(NumX.currencySymbolFor('MMK'), 'K');
    });

    test('compacts large amounts for tight layouts', () {
      expect(1234.0.toCompactCurrency(), r'$1.23K');
      expect((-2500.0).toCompactCurrency(), r'-$2.5K');
    });

    test('signs positive amounts explicitly', () {
      expect(10.0.toSignedCurrency(), r'+$10.00');
      expect((-10.0).toSignedCurrency(), r'-$10.00');
    });

    test('falls back to the ISO code for unknown currencies', () {
      expect(NumX.currencySymbolFor('XYZ'), 'XYZ ');
    });
  });

  group('StringX', () {
    test('validates emails', () {
      expect('ada@example.com'.isValidEmail, isTrue);
      expect('ada@example'.isValidEmail, isFalse);
      expect('not-an-email'.isValidEmail, isFalse);
    });

    test('enforces the password policy', () {
      expect('passw0rd'.isStrongPassword, isTrue);
      expect('password'.isStrongPassword, isFalse);
      expect('pw0rd'.isStrongPassword, isFalse);
    });

    test('derives avatar initials', () {
      expect('Ada Lovelace'.initials, 'AL');
      expect('Ada'.initials, 'A');
      expect('   '.initials, '?');
    });

    test('parses hex colours', () {
      expect('#FF0000'.toColorValue, 0xFFFF0000);
      expect('nope'.toColorValue, isNull);
    });
  });

  group('DateTimeX', () {
    final DateTime wednesday = DateTime(2026, 8, 5, 14, 30);

    test('computes week boundaries from Monday', () {
      expect(wednesday.startOfWeek, DateTime(2026, 8, 3));
      expect(wednesday.endOfWeek.day, 9);
    });

    test('computes month boundaries', () {
      expect(wednesday.startOfMonth, DateTime(2026, 8));
      expect(wednesday.endOfMonth.day, 31);
    });

    test('range check ignores the time component', () {
      expect(wednesday.isBetween(DateTime(2026, 8, 5), DateTime(2026, 8, 5)), isTrue);
      expect(wednesday.isBetween(DateTime(2026, 8, 6), DateTime(2026, 8, 9)), isFalse);
    });
  });
}
