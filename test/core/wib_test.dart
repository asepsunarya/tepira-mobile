import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/wib.dart';

DateTime _utc(String iso) => DateTime.parse(iso);

void main() {
  group('wibDate / wibDayKey', () {
    test('16:59:59.999Z is still the same WIB day (23:59 WIB)', () {
      final instant = _utc('2026-11-01T16:59:59.999Z');

      expect(wibDate(instant), DateTime.utc(2026, 11, 1));
      expect(wibDayKey(instant), '2026-11-01');
    });

    test('17:00Z is 00:00 WIB of the next day', () {
      final instant = _utc('2026-11-01T17:00:00.000Z');

      expect(wibDate(instant), DateTime.utc(2026, 11, 2));
      expect(wibDayKey(instant), '2026-11-02');
    });

    test('an expense at 2026-10-31T17:30Z belongs to 1 November WIB', () {
      expect(wibDayKey(_utc('2026-10-31T17:30:00.000Z')), '2026-11-01');
    });

    test('the year turns at 31 Dec 17:00Z', () {
      expect(wibDayKey(_utc('2026-12-31T16:59:59.999Z')), '2026-12-31');
      expect(wibDayKey(_utc('2026-12-31T17:00:00.000Z')), '2027-01-01');
    });

    test('ignores the zone of a local DateTime (uses the instant)', () {
      final utc = _utc('2026-11-01T17:30:00.000Z');

      expect(wibDayKey(utc.toLocal()), wibDayKey(utc));
    });

    test('pads small years and months', () {
      expect(wibDayKey(DateTime.utc(999, 1, 2, 3)), '0999-01-02');
    });
  });

  group('wibDayStart', () {
    test('is 17:00Z of the previous UTC day', () {
      expect(
        wibDayStart(_utc('2026-11-01T07:00:00.000Z')),
        _utc('2026-10-31T17:00:00.000Z'),
      );
    });

    test('at exactly 00:00 WIB returns that same instant', () {
      final midnight = _utc('2026-11-01T17:00:00.000Z');

      expect(wibDayStart(midnight), midnight);
    });

    test('one millisecond before 00:00 WIB returns the previous day', () {
      expect(
        wibDayStart(_utc('2026-11-01T16:59:59.999Z')),
        _utc('2026-10-31T17:00:00.000Z'),
      );
    });

    test('offsetDays moves across a month end', () {
      final lastDay = _utc('2026-11-30T10:00:00.000Z');

      expect(wibDayStart(lastDay, 1), _utc('2026-11-30T17:00:00.000Z'));
      expect(wibDayKey(wibDayStart(lastDay, 1)), '2026-12-01');
      expect(wibDayStart(lastDay, -30), _utc('2026-10-30T17:00:00.000Z'));
    });

    test('is a UTC DateTime', () {
      expect(wibDayStart(_utc('2026-11-01T07:00:00.000Z')).isUtc, isTrue);
    });
  });

  test('isSameWibDay compares WIB days, not UTC days', () {
    // Same UTC day, different WIB days.
    expect(
      isSameWibDay(
        _utc('2026-11-01T16:59:00.000Z'),
        _utc('2026-11-01T17:01:00.000Z'),
      ),
      isFalse,
    );
    // Different UTC days, same WIB day.
    expect(
      isSameWibDay(
        _utc('2026-10-31T17:01:00.000Z'),
        _utc('2026-11-01T16:59:00.000Z'),
      ),
      isTrue,
    );
  });

  group('WibMonth', () {
    test('of() switches month at 00:00 WIB on the 1st', () {
      expect(
        WibMonth.of(_utc('2026-10-31T16:59:59.999Z')),
        WibMonth(2026, 10),
      );
      expect(
        WibMonth.of(_utc('2026-10-31T17:00:00.000Z')),
        WibMonth(2026, 11),
      );
    });

    test('start and end are 00:00 WIB in UTC, end exclusive', () {
      final november = WibMonth(2026, 11);

      expect(november.start, _utc('2026-10-31T17:00:00.000Z'));
      expect(november.end, _utc('2026-11-30T17:00:00.000Z'));
      expect(november.contains(_utc('2026-10-31T17:00:00.000Z')), isTrue);
      expect(november.contains(_utc('2026-10-31T16:59:59.999Z')), isFalse);
      expect(november.contains(_utc('2026-11-30T16:59:59.999Z')), isTrue);
      expect(november.contains(_utc('2026-11-30T17:00:00.000Z')), isFalse);
    });

    test('December ends at 00:00 WIB on 1 January', () {
      expect(WibMonth(2026, 12).end, _utc('2026-12-31T17:00:00.000Z'));
    });

    test('daysInMonth handles 30, 31 and leap February', () {
      expect(WibMonth(2026, 11).daysInMonth, 30);
      expect(WibMonth(2026, 12).daysInMonth, 31);
      expect(WibMonth(2026, 2).daysInMonth, 28);
      expect(WibMonth(2028, 2).daysInMonth, 29);
    });

    test('next and previous cross the year', () {
      expect(WibMonth(2026, 12).next, WibMonth(2027, 1));
      expect(WibMonth(2027, 1).previous, WibMonth(2026, 12));
      expect(WibMonth(2026, 11).next, WibMonth(2026, 12));
    });

    test('compares by year then month', () {
      expect(WibMonth(2026, 12).compareTo(WibMonth(2027, 1)), isNegative);
      expect(WibMonth(2027, 1).compareTo(WibMonth(2026, 12)), isPositive);
      expect(WibMonth(2026, 11).compareTo(WibMonth(2026, 11)), 0);
    });

    test('equality and hashCode follow year and month', () {
      expect(WibMonth(2026, 11), WibMonth(2026, 11));
      expect(WibMonth(2026, 11).hashCode, WibMonth(2026, 11).hashCode);
      expect(WibMonth(2026, 11), isNot(WibMonth(2025, 11)));
      expect(WibMonth(2026, 11).toString(), '2026-11');
    });

    test('rejects a month outside 1..12', () {
      expect(() => WibMonth(2026, 0), throwsRangeError);
      expect(() => WibMonth(2026, 13), throwsRangeError);
    });
  });

  group('daysLeftInWibMonth (today included)', () {
    test('1 November 07:00 WIB has 30 days left', () {
      expect(daysLeftInWibMonth(_utc('2026-11-01T00:00:00.000Z')), 30);
    });

    test('last day, 23:59 WIB, has 1 day left', () {
      expect(daysLeftInWibMonth(_utc('2026-11-30T16:59:59.999Z')), 1);
    });

    test('00:00 WIB on the 1st starts the next month at its full length', () {
      expect(daysLeftInWibMonth(_utc('2026-11-30T17:00:00.000Z')), 31);
    });

    test('31-day month on the 1st has 31 days left', () {
      expect(daysLeftInWibMonth(_utc('2026-12-01T05:00:00.000Z')), 31);
    });
  });
}
