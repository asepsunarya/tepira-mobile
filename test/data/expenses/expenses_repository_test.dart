import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/wib.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/features/expenses/model/expense.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';

import '../../helpers/fake_http_adapter.dart';
import '../../helpers/fake_session_store.dart';
import '../../helpers/fake_today_repository.dart';

class _Setup {
  _Setup(this.adapter) {
    final dio = createApiDio(
      baseUrl: 'https://api.test/api',
      sessionStore: FakeSessionStore(token: 'jwe-token'),
      onUnauthorized: () {},
    )..httpClientAdapter = adapter;
    repository = ApiExpensesRepository(dio: dio);
  }

  final FakeHttpAdapter adapter;
  late final ExpensesRepository repository;

  RequestOptions get request => adapter.requests.single;

  Object? get sentJson => jsonDecode(jsonEncode(request.data));
}

Map<String, Object?> _error(String code, String message) =>
    {'ok': false, 'error': code, 'message': message};

Expense _row() => Expense(
      id: 1,
      amount: 10000,
      category: null,
      note: null,
      source: 'gaji',
      date: DateTime.utc(2026, 11, 1, 5),
      createdAt: DateTime.utc(2026, 11, 1, 5),
      walletId: 3,
      walletName: 'BCA',
      placeName: null,
    );

ExpenseEdit _edit({required int amount}) => ExpenseEdit(
      amount: amount,
      walletId: 3,
      category: null,
      note: null,
      source: ExpenseSource.gaji,
      day: '2026-11-01',
    );

const _bakso = NewExpense(
  amount: 18000,
  walletId: 3,
  category: 'Makan harian',
  note: 'bakso',
);

void main() {
  group('create', () {
    test('POSTs JSON without a date for today', () async {
      final s = _Setup(
        FakeHttpAdapter(
          status: 201,
          body: readFixture('mobile_expense_created'),
        ),
      );

      final created = await s.repository.create(_bakso);

      expect(s.request.method, 'POST');
      expect(s.request.uri.toString(), 'https://api.test/api/mobile/expenses');
      expect(s.request.contentType, startsWith('application/json'));
      expect(s.request.headers.containsKey('Origin'), isFalse);
      expect(s.sentJson, {
        'amount': 18000,
        'walletId': 3,
        'category': 'Makan harian',
        'note': 'bakso',
        'source': 'gaji',
      });
      expect(created.deduped, isFalse);
      expect(created.expense.id, 500);
    });

    test('sends another WIB day, the source and null category/note', () async {
      final s = _Setup(
        FakeHttpAdapter(
          status: 201,
          body: readFixture('mobile_expense_created'),
        ),
      );

      await s.repository.create(
        const NewExpense(
          amount: 40000,
          walletId: 9,
          note: '  ',
          source: ExpenseSource.bonus,
          day: '2026-10-31',
        ),
      );

      expect(s.sentJson, {
        'amount': 40000,
        'walletId': 9,
        'category': null,
        'note': null,
        'source': 'bonus',
        'date': '2026-10-31',
      });
    });

    test('200 deduped is a success with the stored row, not an error',
        () async {
      final s = _Setup(
        FakeHttpAdapter(body: readFixture('mobile_expense_deduped')),
      );

      final created = await s.repository.create(_bakso);

      expect(created.deduped, isTrue);
      expect(created.expense.id, 500);
      expect(created.wallet!.balance, 8232000);
    });

    test('400 wallet_not_found -> BadRequestException told apart', () {
      final s = _Setup(
        FakeHttpAdapter(
          status: 400,
          body: _error(
            'wallet_not_found',
            'Dompet tidak ditemukan. Pilih dompet lain.',
          ),
        ),
      );

      expect(
        s.repository.create(_bakso),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.code, 'code', 'wallet_not_found')
              .having(
                (e) => e.message,
                'message',
                'Dompet tidak ditemukan. Pilih dompet lain.',
              ),
        ),
      );
    });

    test('400 bad_request keeps the server message', () {
      final s = _Setup(
        FakeHttpAdapter(
          status: 400,
          body: _error('bad_request', kExpenseAmountMessage),
        ),
      );

      expect(
        s.repository.create(_bakso),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.code, 'code', 'bad_request')
              .having((e) => e.message, 'message', kExpenseAmountMessage),
        ),
      );
    });

    test('429 -> RateLimitedException with Retry-After', () {
      final s = _Setup(
        FakeHttpAdapter(
          status: 429,
          headers: const {
            'retry-after': ['2'],
          },
          body: _error(
            'rate_limited',
            'Terlalu banyak permintaan. Coba lagi sebentar lagi.',
          ),
        ),
      );

      expect(
        s.repository.create(_bakso),
        throwsA(
          isA<RateLimitedException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 2),
          ),
        ),
      );
    });

    test('500 with Retry-After -> retryable ServerException', () {
      final s = _Setup(
        FakeHttpAdapter(
          status: 500,
          headers: const {
            'retry-after': ['1'],
          },
          body: _error(
            'server_error',
            'Terjadi kesalahan di server. Coba lagi nanti.',
          ),
        ),
      );

      expect(
        s.repository.create(_bakso),
        throwsA(
          isA<ServerException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 1),
          ),
        ),
      );
    });
  });

  group('list', () {
    test('without a month: no query, the server picks the WIB month', () async {
      final s = _Setup(FakeHttpAdapter(body: readFixture('mobile_expenses')));

      final list = await s.repository.list();

      expect(s.request.method, 'GET');
      expect(s.request.uri.toString(), 'https://api.test/api/mobile/expenses');
      expect(list.expenses, hasLength(3));
    });

    test('sends year and month of a WIB month', () async {
      final s = _Setup(FakeHttpAdapter(body: readFixture('mobile_expenses')));
      // 31 Oct 17:30 UTC is 1 Nov 00:30 WIB.
      final month = WibMonth.of(DateTime.utc(2026, 10, 31, 17, 30));

      await s.repository.list(month: month.previous);

      expect(
        s.request.uri.toString(),
        'https://api.test/api/mobile/expenses?year=2026&month=10',
      );
    });

    test('400 bad month -> BadRequestException', () {
      final s = _Setup(
        FakeHttpAdapter(
          status: 400,
          body: _error('bad_request', 'Bulan atau tahun tidak valid.'),
        ),
      );

      expect(
        s.repository.list(month: WibMonth(2019, 12)),
        throwsA(isA<BadRequestException>()),
      );
    });
  });

  group('update', () {
    test('PATCHes only the given fields, null clears', () async {
      final s = _Setup(
        FakeHttpAdapter(body: readFixture('mobile_expense_updated')),
      );
      final original = (await _Setup(
        FakeHttpAdapter(body: readFixture('mobile_expenses')),
      ).repository.list())
          .expenses
          .first;

      final updated = await s.repository.update(
        499,
        ExpensePatch.between(
          original,
          const ExpenseEdit(
            amount: 25000,
            walletId: 9,
            category: 'Makan harian',
            note: '',
            source: ExpenseSource.gaji,
            day: '2026-11-01',
          ),
        ),
      );

      expect(s.request.method, 'PATCH');
      expect(
        s.request.uri.toString(),
        'https://api.test/api/mobile/expenses/499',
      );
      expect(s.sentJson, {'walletId': 9, 'note': null});
      expect(updated.wallets, hasLength(2));
    });

    test('404 -> NotFoundException', () {
      final s = _Setup(
        FakeHttpAdapter(
          status: 404,
          body: _error('not_found', 'Data tidak ditemukan.'),
        ),
      );

      expect(
        s.repository.update(1, ExpensePatch.between(_row(), _edit(amount: 1))),
        throwsA(isA<NotFoundException>()),
      );
    });
  });

  group('delete', () {
    test('DELETEs the expense and reads the restored wallet', () async {
      final s = _Setup(
        FakeHttpAdapter(body: readFixture('mobile_expense_deleted')),
      );

      final deleted = await s.repository.delete(499);

      expect(s.request.method, 'DELETE');
      expect(
        s.request.uri.toString(),
        'https://api.test/api/mobile/expenses/499',
      );
      expect(s.request.data, isNull);
      expect(deleted.wallet!.id, 3);
    });

    test('404 (already deleted) -> NotFoundException', () {
      final s = _Setup(
        FakeHttpAdapter(
          status: 404,
          body: _error('not_found', 'Data tidak ditemukan.'),
        ),
      );

      expect(s.repository.delete(499), throwsA(isA<NotFoundException>()));
    });
  });
}
