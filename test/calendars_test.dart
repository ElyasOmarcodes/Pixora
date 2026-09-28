import 'package:flutter_test/flutter_test.dart';
import 'package:pixora/core/utils/calendars.dart';

void main() {
  test('solar hijri (Jalali) conversion', () {
    expect(toJalali(DateTime(2024, 3, 20)), (1403, 1, 1));
    expect(toJalali(DateTime(2023, 3, 21)), (1402, 1, 1));
    expect(toJalali(DateTime(2025, 3, 21)), (1404, 1, 1));
    expect(toJalali(DateTime(2024, 12, 21)), (1403, 10, 1));
    expect(toJalali(DateTime(2026, 9, 28)), (1405, 7, 6));
  });

  test('hijri conversion (tabular)', () {
    final (y, m, d) = toHijri(DateTime(2024, 3, 11));
    expect(y, 1445);
    expect(m, anyOf(8, 9));
    expect(d, anyOf(1, 29, 30));
    expect(toHijri(DateTime(2026, 9, 28)).$1, 1448);
  });

  test('digits and items', () {
    expect(applyDigits('2026/09', DigitStyle.persian), '۲۰۲۶/۰۹');
    expect(applyDigits('12', DigitStyle.arabic), '١٢');
    final items = insertItems(
      DateTime(2026, 9, 28, 14, 5),
      'ps',
      DigitStyle.latin,
    );
    expect(items.any((i) => i.text.contains('میزان')), isTrue);
    expect(items.any((i) => i.text.contains('تله')), isTrue);
    expect(items.any((i) => i.text == '14:05'), isTrue);
  });
}
