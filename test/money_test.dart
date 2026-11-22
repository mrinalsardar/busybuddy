import 'package:flutter_test/flutter_test.dart';

import 'package:busybuddy/core/utils/money.dart';

void main() {
  const inr = MoneyFormat('INR', 2);
  const jpy = MoneyFormat('JPY', 0);
  const kwd = MoneyFormat('KWD', 3);

  test('parse reads amounts into minor units for the currency decimals', () {
    expect(inr.parse('12'), 1200);
    expect(inr.parse('12.5'), 1250);
    expect(inr.parse(' 9.99 '), 999);
    expect(inr.parse('7.'), 700);
    expect(jpy.parse('1500'), 1500);
    expect(kwd.parse('1.5'), 1500);
    expect(kwd.parse('0.125'), 125);
  });

  test('parse rejects bad input', () {
    for (final bad in ['', 'abc', '-1', '1.234', '1,5', '.5', '12345678901']) {
      expect(inr.parse(bad), isNull, reason: bad);
    }
    expect(jpy.parse('1.5'), isNull);
    expect(kwd.parse('1.2345'), isNull);
  });

  test('format shows exactly the currency decimals', () {
    expect(inr.format(999), 'INR 9.99');
    expect(inr.format(1000), 'INR 10.00');
    expect(inr.format(5), 'INR 0.05');
    expect(jpy.format(1500), 'JPY 1500');
    expect(kwd.format(1500), 'KWD 1.500');
    expect(inr.toInput(-250), '-2.50');
  });

  test('every picker currency has 0-3 decimals', () {
    expect(currencyDecimals.values.every((d) => d >= 0 && d <= 3), isTrue);
    expect(currencyDecimals['INR'], 2);
  });
}
