/// WIB (UTC+7, no DST) calendar days and months, the way the tepira API
/// counts them (SPEC-v2 §3, backend `lib/mobile/today.ts`).
///
/// Every function takes an instant and works on a fixed +7 hour offset. The
/// device time zone is never used: a phone set to another zone must still
/// group and label expenses by the same WIB day as the server.
library;

/// WIB is UTC+7 all year.
const Duration kWibOffset = Duration(hours: 7);

/// The WIB calendar date of [instant], as a UTC midnight `DateTime` whose
/// year, month and day are the WIB ones. Only the date fields are meaningful.
DateTime wibDate(DateTime instant) {
  final wib = instant.toUtc().add(kWibOffset);
  return DateTime.utc(wib.year, wib.month, wib.day);
}

/// The WIB day of [instant] as `YYYY-MM-DD`, e.g. for grouping or for the
/// `date` field of an expense.
String wibDayKey(DateTime instant) {
  final date = wibDate(instant);
  return '${_pad(date.year, 4)}-${_pad(date.month, 2)}-${_pad(date.day, 2)}';
}

/// The first instant (00:00 WIB) of the WIB day [offsetDays] away from
/// [instant]'s WIB day, in UTC.
DateTime wibDayStart(DateTime instant, [int offsetDays = 0]) {
  final date = wibDate(instant);
  return DateTime.utc(
    date.year,
    date.month,
    date.day + offsetDays,
  ).subtract(kWibOffset);
}

/// True when [a] and [b] fall on the same WIB calendar day.
bool isSameWibDay(DateTime a, DateTime b) => wibDate(a) == wibDate(b);

/// A WIB calendar month, e.g. the `period` `{year, month}` of the API.
class WibMonth implements Comparable<WibMonth> {
  /// [month] is 1..12.
  WibMonth(this.year, this.month) {
    if (month < 1 || month > 12) {
      throw RangeError.range(month, 1, 12, 'month');
    }
  }

  /// The WIB month [instant] falls in.
  factory WibMonth.of(DateTime instant) {
    final date = wibDate(instant);
    return WibMonth(date.year, date.month);
  }

  final int year;
  final int month;

  /// 00:00 WIB on the 1st, in UTC (inclusive).
  DateTime get start => DateTime.utc(year, month).subtract(kWibOffset);

  /// 00:00 WIB on the 1st of the next month, in UTC (exclusive).
  DateTime get end => DateTime.utc(year, month + 1).subtract(kWibOffset);

  /// Number of days in this month (28..31).
  int get daysInMonth => DateTime.utc(year, month + 1, 0).day;

  WibMonth get next =>
      month == 12 ? WibMonth(year + 1, 1) : WibMonth(year, month + 1);

  WibMonth get previous =>
      month == 1 ? WibMonth(year - 1, 12) : WibMonth(year, month - 1);

  /// True when [instant] is inside `[start, end)`.
  bool contains(DateTime instant) =>
      !instant.isBefore(start) && instant.isBefore(end);

  @override
  int compareTo(WibMonth other) =>
      year != other.year ? year - other.year : month - other.month;

  @override
  bool operator ==(Object other) =>
      other is WibMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '${_pad(year, 4)}-${_pad(month, 2)}';
}

/// Days from [now]'s WIB day to the end of its WIB month, today included
/// (1..31), as the backend's `daysLeftInWibMonth`.
int daysLeftInWibMonth(DateTime now) {
  final date = wibDate(now);
  return WibMonth(date.year, date.month).daysInMonth - date.day + 1;
}

String _pad(int value, int width) => value.toString().padLeft(width, '0');
