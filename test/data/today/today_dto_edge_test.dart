import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/wib.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/expenses/expense_dto.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart'
    show kUnrecognizedResponseMessage;
import 'package:tepira_mobile/data/today/today_dto.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';

import '../../helpers/fake_http_adapter.dart';
import '../../helpers/fake_session_store.dart';
import '../../helpers/fake_today_repository.dart';

Map<String, Object?> _with(
  Map<String, Object?> json,
  String object,
  String key,
  Object? value,
) {
  final copy = Map<String, Object?>.of(json);
  copy[object] = {...(json[object] as Map<String, Object?>), key: value};
  return copy;
}

Map<String, Object?> _withDate(
  Map<String, Object?> json,
  String date,
  int year,
  int month,
) =>
    {
      ...json,
      'date': date,
      'period': {
        ...(json['period'] as Map<String, Object?>),
        'year': year,
        'month': month,
      },
    };

Dio _dio(FakeHttpAdapter adapter) => createApiDio(
      baseUrl: 'https://api.test/api',
      sessionStore: FakeSessionStore(token: 'jwe-token'),
      onUnauthorized: () {},
    )..httpClientAdapter = adapter;

void main() {
  final base = readFixture('mobile_today_budget');

  group('unknown enum values are errors, never guessed', () {
    for (final (object, key, value) in [
      ('safeToday', 'state', 'OK'),
      ('safeToday', 'state', ' ok'),
      ('safeToday', 'state', 'overMonth'),
      ('safeToday', 'state', 'over-month'),
      ('safeToday', 'state', ''),
      ('safeToday', 'state', null),
      ('safeToday', 'state', 0),
      ('safeToday', 'basis', 'Budget'),
      ('safeToday', 'basis', 'wallets'),
      ('safeToday', 'basis', null),
      ('budget', 'status', 'within_budget'),
      ('budget', 'status', 'OVER'),
      ('budget', 'status', null),
    ]) {
      test('$object.$key = ${value is String ? '"$value"' : value}', () {
        expect(
          () => todaySummaryFromJson(_with(base, object, key, value)),
          throwsFormatException,
        );
      });
    }

    test('GET /mobile/today with an unknown basis -> ServerException', () {
      final dio = _dio(
        FakeHttpAdapter(body: _with(base, 'safeToday', 'basis', 'savings')),
      );

      expect(
        ApiTodayRepository(dio: dio).get(),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            kUnrecognizedResponseMessage,
          ),
        ),
      );
    });

    test('a write answer whose today has an unknown state -> ServerException',
        () {
      final body = readFixture('mobile_expense_created');
      final dio = _dio(
        FakeHttpAdapter(
          status: 201,
          body: {
            ...body,
            'today': _with(
              body['today'] as Map<String, Object?>,
              'safeToday',
              'state',
              'aman',
            ),
          },
        ),
      );

      expect(
        ApiExpensesRepository(dio: dio)
            .create(const NewExpense(amount: 1, walletId: 3)),
        throwsA(isA<ServerException>()),
      );
    });

    test('a write answer with an unknown budget status fails to parse', () {
      final body = readFixture('mobile_expense_deduped');
      expect(
        () => expenseCreatedFromJson({
          ...body,
          'today': _with(
            body['today'] as Map<String, Object?>,
            'budget',
            'status',
            'NOPE',
          ),
        }),
        throwsFormatException,
      );
    });
  });

  group('WIB month boundaries in the summary', () {
    test('1 Dec: period December, the date is that WIB day', () {
      final summary = todaySummaryFromJson(
        _withDate(base, '2026-12-01', 2026, 12),
      );

      expect(summary.period.month, WibMonth(2026, 12));
      expect(summary.date, DateTime.utc(2026, 12, 1));
      // The WIB day the date stands for starts at 30 Nov 17:00Z.
      expect(
        wibDayStart(summary.date.subtract(kWibOffset)),
        DateTime.utc(2026, 11, 30, 17),
      );
    });

    test('31 Dec -> 1 Jan of the next year', () {
      final summary = todaySummaryFromJson(
        _withDate(base, '2027-01-01', 2027, 1),
      );

      expect(summary.period.month, WibMonth(2027, 1));
      expect(summary.date, DateTime.utc(2027, 1, 1));
    });

    test('29 Feb in a leap year is a date; in another year it is not', () {
      expect(
        todaySummaryFromJson(_withDate(base, '2028-02-29', 2028, 2)).date,
        DateTime.utc(2028, 2, 29),
      );
      expect(
        () => todaySummaryFromJson(_withDate(base, '2027-02-29', 2027, 2)),
        throwsFormatException,
      );
    });

    for (final bad in ['2026-11-31', '2026-13-01', '2026-00-10', '2026-1-01']) {
      test('"$bad" is refused', () {
        expect(
          () => todaySummaryFromJson({...base, 'date': bad}),
          throwsFormatException,
        );
      });
    }
  });

  group('expense list month boundaries', () {
    Map<String, Object?> row(int id, String date) => {
          'id': id,
          'amount': 1000,
          'category': null,
          'note': null,
          'source': 'gaji',
          'date': date,
          'createdAt': date,
          'walletId': 3,
          'walletName': 'BCA',
          'placeName': null,
        };

    test('rows at 16:59:59.999Z and 17:00Z on 30 Nov fall in two WIB months',
        () {
      final list = expenseListFromJson({
        'ok': true,
        'asOf': '2026-11-30T17:00:00.000Z',
        'period': {'year': 2026, 'month': 12},
        'total': 1000,
        'count': 1,
        'more': false,
        'expenses': [
          row(2, '2026-11-30T17:00:00.000Z'),
          row(1, '2026-11-30T16:59:59.999Z'),
        ],
      });

      final dec = WibMonth(2026, 12);
      expect(list.period, dec);
      expect(dec.contains(list.expenses[0].date), isTrue);
      expect(dec.contains(list.expenses[1].date), isFalse);
      expect(wibDayKey(list.expenses[0].date), '2026-12-01');
      expect(wibDayKey(list.expenses[1].date), '2026-11-30');
    });
  });

  group('NewExpense date rule', () {
    test('no day -> the body has no "date" key, not null', () {
      final json = const NewExpense(amount: 10000, walletId: 3).toJson();

      expect(json.containsKey('date'), isFalse);
    });

    test('another day -> "date" is that YYYY-MM-DD', () {
      final json = NewExpense(
        amount: 10000,
        walletId: 3,
        day: wibDayKey(DateTime.utc(2026, 11, 24, 17)),
      ).toJson();

      expect(json['date'], '2026-11-25');
    });
  });
}
