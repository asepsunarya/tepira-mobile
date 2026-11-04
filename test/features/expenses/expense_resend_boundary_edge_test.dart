// Independent edge tests for the resend rule (fix round on PR #22): only a
// 500 `server_error` whose Retry-After is at most 5 s is sent again; the
// boundary, a missing header and unparseable headers are never resent.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/expense_providers.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/fake_session_store.dart';
import '../../helpers/fake_today_repository.dart';
import '../../helpers/fake_wallets_repository.dart';

const _body = NewExpense(amount: 25000, walletId: 9);

/// The [ServerException] the real dio mapping makes from a 500
/// `server_error` answer carrying [retryAfter] (null: no header).
Future<ServerException> _mapped500(String? retryAfter) async {
  final dio = createApiDio(
    baseUrl: 'https://api.test/api',
    sessionStore: FakeSessionStore(),
  )..httpClientAdapter = FakeHttpAdapter(
      status: 500,
      headers: {
        if (retryAfter != null) 'retry-after': [retryAfter],
      },
      body: {'ok': false, 'error': 'server_error', 'message': 'Coba lagi.'},
    );
  try {
    await dio.post<Object?>('/mobile/expenses', data: {'a': 1});
  } on DioException catch (e) {
    return e.error! as ServerException;
  }
  fail('request did not fail');
}

ProviderContainer _container(FakeExpensesRepository expenses) {
  final container = ProviderContainer(
    overrides: [
      expensesRepositoryProvider.overrideWithValue(expenses),
      walletsRepositoryProvider
          .overrideWithValue(FakeWalletsRepository([fixtureWalletList()])),
      todayRepositoryProvider.overrideWithValue(FakeTodayRepository.budget()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('retryWaitOf boundaries', () {
    test('the max resend wait is 5 s', () {
      expect(kMaxExpenseResendWait, const Duration(seconds: 5));
    });

    test('Retry-After exactly 5 s is resent after 5 s', () {
      expect(
        retryWaitOf(
          const ServerException(
            statusCode: 500,
            code: 'server_error',
            retryAfter: Duration(seconds: 5),
          ),
        ),
        const Duration(seconds: 5),
      );
    });

    test('Retry-After 0 is resent at once', () {
      expect(
        retryWaitOf(
          const ServerException(
            statusCode: 500,
            code: 'server_error',
            retryAfter: Duration.zero,
          ),
        ),
        Duration.zero,
      );
    });

    test('just over 5 s (5.001 s and 6 s) is not resent', () {
      for (final wait in const [
        Duration(milliseconds: 5001),
        Duration(seconds: 6),
        Duration(seconds: 300),
      ]) {
        expect(
          retryWaitOf(
            ServerException(
              statusCode: 500,
              code: 'server_error',
              retryAfter: wait,
            ),
          ),
          isNull,
          reason: '$wait',
        );
      }
    });

    test('a 500 with another or no error code is not resent', () {
      for (final code in [null, 'internal', 'SERVER_ERROR', 'server_error ']) {
        expect(
          retryWaitOf(
            ServerException(
              statusCode: 500,
              code: code,
              retryAfter: const Duration(seconds: 1),
            ),
          ),
          isNull,
          reason: '$code',
        );
      }
    });

    test('server_error on a status other than 500 is not resent', () {
      for (final status in [null, 499, 501, 502, 503, 504]) {
        expect(
          retryWaitOf(
            ServerException(
              statusCode: status,
              code: 'server_error',
              retryAfter: const Duration(seconds: 1),
            ),
          ),
          isNull,
          reason: '$status',
        );
      }
    });
  });

  group('Retry-After header through the real mapping', () {
    test('"5" gives a 5 s resend', () async {
      expect(retryWaitOf(await _mapped500('5')), const Duration(seconds: 5));
    });

    test('"6" is not resent', () async {
      expect(retryWaitOf(await _mapped500('6')), isNull);
    });

    test('a missing header is not resent', () async {
      final error = await _mapped500(null);
      expect(error.retryAfter, isNull);
      expect(retryWaitOf(error), isNull);
    });

    test('non-numeric, HTTP-date, fractional, signed values are not resent',
        () async {
      for (final value in [
        '',
        'abc',
        'soon',
        'Wed, 04 Nov 2026 04:52:03 GMT',
        '1.5',
        '5.0',
        '-1',
        '+1',
        '1e0',
        '0x5',
      ]) {
        final error = await _mapped500(value);
        expect(error.code, 'server_error', reason: value);
        expect(retryWaitOf(error), isNull, reason: value);
      }
    });
  });

  group('ExpenseWriter.create at the boundary', () {
    testWidgets('Retry-After 5 s: waits the full 5 s, then resends once',
        (tester) async {
      final expenses = FakeExpensesRepository(
        createResults: [
          const ServerException(
            statusCode: 500,
            code: 'server_error',
            retryAfter: Duration(seconds: 5),
          ),
          fixtureExpenseCreated(),
        ],
      );
      final writer = _container(expenses).read(expenseWriterProvider);

      var done = false;
      final pending = writer.create(_body).then((_) => done = true);
      await tester.pump(const Duration(milliseconds: 4999));
      expect(expenses.created, hasLength(1));
      expect(done, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      await pending;

      expect(done, isTrue);
      expect(expenses.created, hasLength(2));
    });

    testWidgets('Retry-After 6 s: thrown at once, not resent', (tester) async {
      const error = ServerException(
        statusCode: 500,
        code: 'server_error',
        retryAfter: Duration(seconds: 6),
      );
      final expenses = FakeExpensesRepository(
        createResults: [error, fixtureExpenseCreated()],
      );
      final writer = _container(expenses).read(expenseWriterProvider);

      Object? thrown;
      await writer.create(_body).then<void>(
            (_) {},
            onError: (Object e) => thrown = e,
          );

      expect(thrown, same(error));
      await tester.pump(const Duration(seconds: 10));
      expect(expenses.created, hasLength(1));
    });

    testWidgets('a second 500 server_error on the resend is not resent again',
        (tester) async {
      const error = ServerException(
        statusCode: 500,
        code: 'server_error',
        retryAfter: Duration(seconds: 1),
      );
      final expenses = FakeExpensesRepository(
        createResults: [error, error, fixtureExpenseCreated()],
      );
      final writer = _container(expenses).read(expenseWriterProvider);

      Object? thrown;
      final pending = writer.create(_body).then<void>(
            (_) {},
            onError: (Object e) => thrown = e,
          );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await pending;

      expect(thrown, same(error));
      await tester.pump(const Duration(seconds: 10));
      expect(expenses.created, hasLength(2));
    });
  });
}
