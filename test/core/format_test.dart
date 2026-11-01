import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/format.dart';

void main() {
  test('formats whole rupiah with dot separators and no decimals', () {
    expect(formatRupiah(1500000), 'Rp1.500.000');
  });

  test('formats zero', () {
    expect(formatRupiah(0), 'Rp0');
  });

  test('formats a calendar date with Indonesian short month names', () {
    expect(formatShortDate(DateTime.utc(2027, 4, 30)), '30 Apr 2027');
    expect(formatShortDate(DateTime.utc(2026, 5, 1)), '1 Mei 2026');
    expect(formatShortDate(DateTime.utc(2026, 8, 17)), '17 Agu 2026');
    expect(formatShortDate(DateTime.utc(2026, 10, 28)), '28 Okt 2026');
    expect(formatShortDate(DateTime.utc(2026, 12, 31)), '31 Des 2026');
  });

  test('uses the date fields as given, without converting time zones', () {
    expect(formatShortDate(DateTime.utc(2026, 1, 1, 23, 30)), '1 Jan 2026');
  });
}
