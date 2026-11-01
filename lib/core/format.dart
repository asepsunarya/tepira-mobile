import 'package:intl/intl.dart';

final NumberFormat _rupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp',
  decimalDigits: 0,
);

/// Formats whole rupiah: 1500000 -> "Rp1.500.000".
String formatRupiah(int amount) => _rupiah.format(amount);
