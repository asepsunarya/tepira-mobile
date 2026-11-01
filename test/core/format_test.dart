import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/format.dart';

void main() {
  test('formats whole rupiah with dot separators and no decimals', () {
    expect(formatRupiah(1500000), 'Rp1.500.000');
  });

  test('formats zero', () {
    expect(formatRupiah(0), 'Rp0');
  });
}
