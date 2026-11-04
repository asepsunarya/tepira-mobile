import 'package:intl/intl.dart';

final NumberFormat _rupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp',
  decimalDigits: 0,
);

/// Formats whole rupiah: 1500000 -> "Rp1.500.000".
String formatRupiah(int amount) => _rupiah.format(amount);

const List<String> _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// Formats the calendar fields of [date] as given, without any time zone
/// conversion: 2027-04-30 -> "30 Apr 2027". Convert instants with
/// `toLocal()` first; calendar dates at UTC midnight pass as they are.
String formatShortDate(DateTime date) =>
    '${date.day} ${_shortMonths[date.month - 1]} ${date.year}';

const List<String> _months = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', //
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

/// The name of calendar [month] (1..12): 10 -> "Oktober".
String formatMonthName(int month) => _months[month - 1];

/// Formats a calendar month: (2026, 11) -> "November 2026".
String formatMonthYear(int year, int month) => '${_months[month - 1]} $year';
