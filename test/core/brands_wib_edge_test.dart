// Independent edge cases for brand logo matching and WIB boundaries.
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/brands.dart';
import 'package:tepira_mobile/core/wib.dart';

void main() {
  group('brandForWalletName edges', () {
    test('BCA family: card, blu and Flazz', () {
      expect(brandForWalletName('Kartu kredit BCA')?.name, 'BCA');
      expect(brandForWalletName('KARTU KREDIT bca')?.name, 'BCA');
      expect(brandForWalletName('blu by BCA')?.name, 'blu by BCA');
      expect(brandForWalletName('BLU BY bca')?.name, 'blu by BCA');
      expect(brandForWalletName('Tabungan blu')?.name, 'blu by BCA');
      expect(brandForWalletName('flazz')?.name, 'BCA Flazz');
    });

    test('no partial-word matches', () {
      for (final name in [
        'BCAX',
        'xBCA',
        'BCA2',
        'Mandirian',
        'Danamon',
        'Ovoid',
        'Bluebird',
        'Gopayment',
        'Jagoan',
        'Flipper',
        'Brizzia',
      ]) {
        expect(brandForWalletName(name), isNull, reason: name);
      }
    });

    test('tabs and newlines count as spaces', () {
      expect(brandForWalletName('kartu\tBCA\n')?.name, 'BCA');
      expect(brandForWalletName('link\t aja')?.name, 'LinkAja');
    });

    test('aliases resolve to their brand', () {
      expect(brandForWalletName('Bank Jago')?.name, 'Jago');
      expect(brandForWalletName('sea bank')?.name, 'SeaBank');
      expect(brandForWalletName('emoney kantor')?.name, 'Mandiri e-money');
      expect(brandForWalletName('Kartu TapCash')?.name, 'BNI TapCash');
    });

    test('every picker brand finds itself by its own name', () {
      for (final brand in kPickerBrands) {
        expect(brandForWalletName(brand.name), same(brand), reason: brand.name);
      }
    });
  });

  group('WIB month boundaries', () {
    test('November 2026 starts 31 Oct 17:00Z and ends 30 Nov 17:00Z', () {
      final nov = WibMonth(2026, 11);
      expect(nov.start, DateTime.utc(2026, 10, 31, 17));
      expect(nov.end, DateTime.utc(2026, 11, 30, 17));
      expect(nov.contains(DateTime.utc(2026, 10, 31, 16, 59, 59, 999)), false);
      expect(nov.contains(DateTime.utc(2026, 10, 31, 17)), true);
      expect(nov.contains(DateTime.utc(2026, 11, 30, 16, 59, 59, 999)), true);
      expect(nov.contains(DateTime.utc(2026, 11, 30, 17)), false);
    });

    test('January starts on 31 Dec 17:00Z of the previous year', () {
      final jan = WibMonth(2027, 1);
      expect(jan.start, DateTime.utc(2026, 12, 31, 17));
      expect(WibMonth.of(DateTime.utc(2026, 12, 31, 17)), jan);
      expect(
        WibMonth.of(DateTime.utc(2026, 12, 31, 16, 59, 59, 999)),
        WibMonth(2026, 12),
      );
      expect(WibMonth(2026, 12).end, jan.start);
      expect(WibMonth(2026, 12).next, jan);
      expect(jan.previous, WibMonth(2026, 12));
    });

    test('March starts 28/29 Feb 17:00Z (leap and non-leap)', () {
      expect(WibMonth(2027, 3).start, DateTime.utc(2027, 2, 28, 17));
      expect(WibMonth(2028, 3).start, DateTime.utc(2028, 2, 29, 17));
      expect(WibMonth(2028, 2).daysInMonth, 29);
      expect(WibMonth(2100, 2).daysInMonth, 28);
    });

    test('every month of 2026 is exactly 24h * days long (no DST)', () {
      for (var m = 1; m <= 12; m++) {
        final month = WibMonth(2026, m);
        expect(
          month.end.difference(month.start),
          Duration(days: month.daysInMonth),
          reason: '$month',
        );
        expect(month.start.hour, 17, reason: '$month');
        expect(month.start.isUtc, true);
      }
    });

    test('wibDayStart(-1) across New Year', () {
      final jan1 = DateTime.utc(2026, 12, 31, 18); // 01:00 WIB 1 Jan 2027
      expect(wibDayKey(jan1), '2027-01-01');
      expect(wibDayStart(jan1), DateTime.utc(2026, 12, 31, 17));
      expect(wibDayStart(jan1, -1), DateTime.utc(2026, 12, 30, 17));
      expect(wibDayStart(jan1, 1), DateTime.utc(2027, 1, 1, 17));
    });

    test('daysLeftInWibMonth at 31 Dec 17:00Z is January (31)', () {
      expect(daysLeftInWibMonth(DateTime.utc(2026, 12, 31, 17)), 31);
      expect(daysLeftInWibMonth(DateTime.utc(2026, 12, 31, 16, 59)), 1);
    });

    test('a non-UTC offset instant gives the same WIB month', () {
      // 2026-10-31T23:30-05:00 == 2026-11-01T04:30Z == 11:30 WIB 1 Nov.
      final instant = DateTime.parse('2026-10-31T23:30:00-05:00');
      expect(WibMonth.of(instant), WibMonth(2026, 11));
      expect(wibDayKey(instant), '2026-11-01');
    });
  });
}
