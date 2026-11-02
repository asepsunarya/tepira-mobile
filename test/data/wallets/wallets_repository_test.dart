import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart'
    show kUnrecognizedResponseMessage;
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';
import 'package:tepira_mobile/features/wallets/model/wallet_input.dart';

import '../../helpers/fake_http_adapter.dart';
import '../../helpers/fake_session_store.dart';

Map<String, Object?> _fixture() =>
    jsonDecode(File('test/fixtures/mobile_wallets.json').readAsStringSync())
        as Map<String, Object?>;

Map<String, Object?> _writeBody({int index = 0}) {
  final fixture = _fixture();
  return {
    'ok': true,
    'wallet': (fixture['wallets'] as List)[index],
    'totals': fixture['totals'],
  };
}

class _Setup {
  _Setup(this.adapter) {
    final dio = createApiDio(
      baseUrl: 'https://api.test/api',
      sessionStore: FakeSessionStore(token: 'jwe-token'),
      onUnauthorized: () => unauthorizedEvents++,
    )..httpClientAdapter = adapter;
    repository = ApiWalletsRepository(dio: dio);
  }

  final FakeHttpAdapter adapter;
  late final WalletsRepository repository;
  int unauthorizedEvents = 0;

  RequestOptions get request => adapter.requests.single;

  Object? get sentJson => jsonDecode(jsonEncode(request.data));
}

const _bca = Wallet(
  id: 3,
  name: 'BCA',
  type: 'bank',
  balance: 8250000,
  displayBalance: 8250000,
  isDebt: false,
  isReserved: false,
  description: null,
  sortOrder: 0,
  spentThisMonth: 25000,
);

void main() {
  group('list', () {
    test('GETs /mobile/wallets with the session cookie', () async {
      final s = _Setup(FakeHttpAdapter(body: _fixture()));

      final list = await s.repository.list();

      expect(s.request.method, 'GET');
      expect(s.request.uri.toString(), 'https://api.test/api/mobile/wallets');
      expect(
        s.request.headers['Cookie'],
        '__Secure-authjs.session-token=jwe-token',
      );
      expect(list.wallets, hasLength(4));
      expect(list.totals.free, 7070000);
    });

    test('a body that breaks the contract -> ServerException', () async {
      final s = _Setup(FakeHttpAdapter(body: {'ok': true, 'wallets': 'x'}));

      await expectLater(
        s.repository.list(),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            kUnrecognizedResponseMessage,
          ),
        ),
      );
    });

    test('a non-object body -> ServerException', () async {
      final s = _Setup(FakeHttpAdapter(body: ['x']));

      await expectLater(s.repository.list(), throwsA(isA<ServerException>()));
    });

    test('401 throws and reports the expired session', () async {
      final s = _Setup(
        FakeHttpAdapter(
          status: 401,
          body: {'ok': false, 'error': 'unauthorized', 'message': 'x'},
        ),
      );

      await expectLater(
        s.repository.list(),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(s.unauthorizedEvents, 1);
    });
  });

  group('create', () {
    test('POSTs the wallet as JSON and returns wallet + totals', () async {
      final s = _Setup(FakeHttpAdapter(status: 201, body: _writeBody()));

      final write = await s.repository.create(
        const NewWallet(name: 'BCA', type: 'bank', balance: 8250000),
      );

      expect(s.request.method, 'POST');
      expect(s.request.uri.path, '/api/mobile/wallets');
      expect(s.request.contentType, startsWith('application/json'));
      expect(s.sentJson, {
        'name': 'BCA',
        'type': 'bank',
        'balance': 8250000,
        'isDebt': false,
        'isReserved': false,
        'description': null,
      });
      expect(write.wallet, _bca);
      expect(write.totals.assets, 11270000);
    });

    test('400 keeps the server validation message', () async {
      const message = 'Dompet tidak bisa sekaligus utang dan dana dicadangkan.';
      final s = _Setup(
        FakeHttpAdapter(
          status: 400,
          body: {'ok': false, 'error': 'bad_request', 'message': message},
        ),
      );

      await expectLater(
        s.repository.create(
          const NewWallet(name: 'KK', type: 'credit', isReserved: true),
        ),
        throwsA(
          isA<BadRequestException>()
              .having((e) => e.code, 'code', 'bad_request')
              .having((e) => e.message, 'message', message),
        ),
      );
    });

    test('429 surfaces RateLimitedException with Retry-After', () async {
      final s = _Setup(
        FakeHttpAdapter(
          status: 429,
          headers: {
            'retry-after': ['12'],
          },
          body: {'ok': false, 'error': 'rate_limited', 'message': 'x'},
        ),
      );

      await expectLater(
        s.repository.create(const NewWallet(name: 'x', type: 'cash')),
        throwsA(
          isA<RateLimitedException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 12),
          ),
        ),
      );
    });
  });

  group('update', () {
    test('PATCHes only the changed fields', () async {
      final s = _Setup(FakeHttpAdapter(body: _writeBody()));

      await s.repository.update(
        3,
        WalletPatch.between(
          _bca,
          const WalletEdit(
            name: 'BCA Utama',
            type: 'bank',
            balance: 8250000,
            isReserved: false,
            description: null,
          ),
        ),
      );

      expect(s.request.method, 'PATCH');
      expect(s.request.uri.path, '/api/mobile/wallets/3');
      expect(s.request.contentType, startsWith('application/json'));
      expect(s.sentJson, {'name': 'BCA Utama'});
    });

    test('sends null to clear the description', () async {
      final s = _Setup(FakeHttpAdapter(body: _writeBody(index: 1)));
      final reserved = (await _Setup(
        FakeHttpAdapter(body: _fixture()),
      ).repository.list())
          .wallets[1];

      await s.repository.update(
        reserved.id,
        WalletPatch.between(
          reserved,
          WalletEdit(
            name: reserved.name,
            type: reserved.type,
            balance: reserved.balance,
            isReserved: reserved.isReserved,
            description: '',
          ),
        ),
      );

      expect(s.sentJson, {'description': null});
    });

    test('404 -> NotFoundException', () async {
      final s = _Setup(
        FakeHttpAdapter(
          status: 404,
          body: {'ok': false, 'error': 'not_found', 'message': 'x'},
        ),
      );

      await expectLater(
        s.repository.update(
          99,
          WalletPatch.between(
            _bca,
            const WalletEdit(
              name: 'x',
              type: 'bank',
              balance: 8250000,
              isReserved: false,
              description: null,
            ),
          ),
        ),
        throwsA(isA<NotFoundException>()),
      );
    });
  });
}
