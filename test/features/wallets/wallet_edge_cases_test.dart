// Independent edge-case tests for the Dompet screen (T15) and the wallet
// form (T16), checked against SPEC-v2 §3.1–3.3, §4 `wallets` and
// docs/api-contract-v2.md §2–4.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/core/widgets/village_chip.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';
import 'package:tepira_mobile/features/wallets/model/wallet_form_rules.dart';
import 'package:tepira_mobile/features/wallets/model/wallet_input.dart';
import 'package:tepira_mobile/features/wallets/wallet_form_screen.dart';
import 'package:tepira_mobile/features/wallets/wallets_screen.dart';
import 'package:tepira_mobile/features/wallets/widgets/wallet_row.dart';

import '../../helpers/fake_wallets_repository.dart';

const _totals = WalletTotals(
  assets: 1000,
  debts: 0,
  reserved: 0,
  netWorth: 1000,
  free: 1000,
);

Future<GoRouter> _pump(
  WidgetTester tester,
  FakeWalletsRepository repository, {
  String location = WalletRoutes.list,
  Size size = const Size(390, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: WalletRoutes.list,
    routes: [
      GoRoute(
        path: WalletRoutes.list,
        builder: (context, state) => const WalletsScreen(),
      ),
      GoRoute(
        path: WalletRoutes.create,
        builder: (context, state) => const WalletFormScreen.create(),
      ),
      GoRoute(
        path: WalletRoutes.editPattern,
        builder: (context, state) => WalletFormScreen.edit(
          walletId: WalletRoutes.parseId(state.pathParameters['id']!),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [walletsRepositoryProvider.overrideWithValue(repository)],
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
  if (location != WalletRoutes.list) {
    unawaited(router.push(location));
    await tester.pumpAndSettle();
  }
  return router;
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

void main() {
  group('rules vs server (lib/mobile/wallets.ts at f74d790)', () {
    test('int32 edges with grouping parse; one past fails', () {
      expect(parseWalletBalance('2.147.483.647'), 2147483647);
      expect(parseWalletBalance('-2.147.483.648'), -2147483648);
      expect(parseWalletBalance('2.147.483.648'), isNull);
      expect(parseWalletBalance('-2.147.483.649'), isNull);
      expect(parseWalletBalance('-0'), 0);
      expect(parseWalletBalance('0'), 0);
      expect(parseWalletBalance('--5'), isNull);
      expect(parseWalletBalance('5-'), isNull);
    });

    test('a zero amount owed is fine for a new debt wallet', () {
      expect(walletBalanceError('0', isDebt: true), isNull);
      expect(walletBalanceError('', isDebt: true), isNull);
    });

    test('a changed negative balance on a legacy negative debt is refused', () {
      final legacy = testWallet(id: 5, balance: -1000, isDebt: true);
      expect(
        walletBalanceError('-1.000', isDebt: true, original: legacy),
        isNull,
      );
      expect(
        walletBalanceError('-2.000', isDebt: true, original: legacy),
        kWalletDebtNegativeError,
      );
    });

    test(
      'a 31-emoji name (31 code points, 62 UTF-16 units) passes, as on the '
      'server',
      () => expect(walletNameError('😀' * 31), isNull),
    );

    test(
      'a 150-emoji description (150 code points) passes, as on the server',
      () => expect(walletDescriptionError('😀' * 150), isNull),
    );

    test('a 60 code-point BMP name passes, 61 fails', () {
      expect(walletNameError('é' * 60), isNull);
      expect(walletNameError('é' * 61), kWalletNameError);
    });

    test('names the server accepts: inner spaces, punctuation', () {
      expect(walletNameError('  Bank Jago — Kantong #1 (ok)  '), isNull);
    });

    test('tab / newline / DEL inside a name fail like the server', () {
      expect(walletNameError('A\tB'), kWalletNameError);
      expect(walletNameError('A\nB'), kWalletNameError);
      expect(walletNameError('A\u007fB'), kWalletNameError);
    });

    test('edit patch: whitespace-only name change sends nothing', () {
      final original = testWallet(id: 3, name: 'BCA', description: 'x');
      final patch = WalletPatch.between(
        original,
        const WalletEdit(
          name: '  BCA  ',
          type: 'bank',
          balance: 8250000,
          isReserved: false,
          description: ' x ',
        ),
      );
      expect(patch.isEmpty, isTrue);
    });

    test('edit patch: clearing the description sends null only', () {
      final original = testWallet(id: 3, description: 'Haji');
      final patch = WalletPatch.between(
        original,
        const WalletEdit(
          name: 'BCA',
          type: 'bank',
          balance: 8250000,
          isReserved: false,
          description: '   ',
        ),
      );
      expect(patch.toJson(), {'description': null});
    });
  });

  group('Dompet screen edges', () {
    testWidgets('empty list: zero totals, the call to action, no groups',
        (tester) async {
      await _pump(tester, FakeWalletsRepository([testWalletList([])]));

      expect(
        tester.widget<Text>(find.byKey(const Key('total-assets'))).data,
        'Rp0',
      );
      expect(find.byKey(const Key('total-debts')), findsNothing);
      expect(find.text('Buat dompet pertamamu'), findsOneWidget);
      for (final title in kWalletGroupTitles.values) {
        expect(find.textContaining('${title.toUpperCase()} · '), findsNothing);
      }
      expect(find.byKey(const Key('add-wallet')), findsNothing);
    });

    testWidgets('totals are shown as sent, not recomputed from the rows',
        (tester) async {
      // Deliberately inconsistent with the rows: the head must follow the
      // server's totals (SPEC-v2 §7).
      final list = testWalletList(
        [testWallet(id: 1, balance: 5)],
        totals: const WalletTotals(
          assets: 777,
          debts: 333,
          reserved: 111,
          netWorth: 444,
          free: -222,
        ),
      );
      await _pump(tester, FakeWalletsRepository([list]));

      expect(
        tester.widget<Text>(find.byKey(const Key('total-assets'))).data,
        'Rp777',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('total-debts'))).data,
        'Utang Rp333',
      );
      expect(find.bySemanticsLabel('Uang bebas -Rp222'), findsOneWidget);
      expect(find.bySemanticsLabel('Dana dicadangkan Rp111'), findsOneWidget);
    });

    testWidgets(
        'huge balances and a 60-char name fit a 320 px screen without '
        'overflow', (tester) async {
      final list = testWalletList(
        [
          testWallet(
            id: 1,
            name: 'W' * 60,
            balance: 2147483647,
            spentThisMonth: 2147483647,
          ),
          testWallet(
            id: 2,
            name: 'M' * 60,
            type: 'credit',
            balance: -2147483648,
            isDebt: true,
          ),
          testWallet(
            id: 3,
            name: 'R' * 60,
            balance: -2147483648,
            isReserved: true,
          ),
        ],
        totals: const WalletTotals(
          assets: 999999999999,
          debts: 999999999999,
          reserved: 999999999999,
          netWorth: 0,
          free: -999999999999,
        ),
      );
      await _pump(
        tester,
        FakeWalletsRepository([list]),
        size: const Size(320, 2400),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(WalletRow), findsNWidgets(3));
      // Debt with a negative raw balance still displays negative and red.
      final debtBalance = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('wallet-2')),
          matching: find.byKey(const Key('wallet-balance')),
        ),
      );
      expect(debtBalance.data, '-Rp2.147.483.648');
    });

    testWidgets('a zero-balance debt still sits in the debt group',
        (tester) async {
      await _pump(
        tester,
        FakeWalletsRepository([
          testWalletList([
            testWallet(id: 4, type: 'paylater', balance: 0, isDebt: true),
          ]),
        ]),
      );
      expect(
        find.text('${kWalletGroupTitles[WalletKind.debt]!.toUpperCase()} · 1'),
        findsOneWidget,
      );
      expect(find.text('SALDO & TABUNGAN · 1'), findsNothing);
    });

    testWidgets('a reserved debt (bad legacy data) is listed as debt',
        (tester) async {
      await _pump(
        tester,
        FakeWalletsRepository([
          testWalletList([
            testWallet(id: 4, type: 'credit', isDebt: true, isReserved: true),
          ]),
        ]),
      );
      expect(find.text('KARTU KREDIT & CICILAN · 1'), findsOneWidget);
      expect(find.text('DANA DICADANGKAN · 1'), findsNothing);
    });

    testWidgets('a failed pull-to-refresh shows the error, then recovers',
        (tester) async {
      final repository = FakeWalletsRepository([
        fixtureWalletList(),
        const NetworkException(),
        fixtureWalletList(),
      ]);
      await _pump(tester, repository, size: const Size(390, 1400));

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Peti harta sedang offline'), findsOneWidget);

      await tester.tap(find.byKey(const Key('retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wallet-3')), findsOneWidget);
      expect(repository.listCalls, 3);
    });
  });

  group('wallet form edges', () {
    testWidgets('two taps in the same frame send one create', (tester) async {
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        createResults: [
          WalletWrite(wallet: testWallet(id: 30), totals: _totals),
        ],
      )..writeGate = Completer<void>();
      await _pump(tester, repository, location: WalletRoutes.create);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.tap(find.byKey(const Key('submit')));
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      expect(repository.created, hasLength(1));

      repository.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(WalletsScreen), findsOneWidget);
      expect(repository.created, hasLength(1));
    });

    testWidgets('two taps in the same frame send one update', (tester) async {
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        updateResults: [
          WalletWrite(
            wallet: testWallet(id: 3, name: 'BCA Utama'),
            totals: _totals,
          ),
        ],
      )..writeGate = Completer<void>();
      await _pump(tester, repository, location: WalletRoutes.edit(3));

      await tester.enterText(find.byKey(const Key('name')), 'BCA Utama');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      expect(repository.updated, hasLength(1));
      expect(repository.updated.single.$2, {'name': 'BCA Utama'});

      repository.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(WalletsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-3')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('total-assets'))).data,
        'Rp1.000',
      );
      expect(repository.listCalls, 1);
    });

    for (final (label, error) in <(String, AppException)>[
      ('401', const UnauthorizedException()),
      ('403', const ForbiddenException(code: 'forbidden_origin')),
      ('404', const NotFoundException()),
      (
        '429',
        const RateLimitedException(
          message: 'Terlalu banyak permintaan. Coba lagi sebentar lagi.',
        ),
      ),
      ('422 (unexpected)', const ApiException('Gagal.', statusCode: 422)),
      ('500', const ServerException()),
    ]) {
      testWidgets(
          'update failure $label: message shown, form kept, retry possible',
          (tester) async {
        final repository = FakeWalletsRepository(
          [fixtureWalletList()],
          updateResults: [
            error,
            WalletWrite(
              wallet: testWallet(id: 3, name: 'BCA Utama'),
              totals: _totals,
            ),
          ],
        );
        await _pump(tester, repository, location: WalletRoutes.edit(3));

        await tester.enterText(find.byKey(const Key('name')), 'BCA Utama');
        await tester.tap(find.byKey(const Key('submit')));
        await tester.pumpAndSettle();

        expect(
          tester.widget<Text>(find.byKey(const Key('submitError'))).data,
          error.message,
        );
        expect(find.byType(WalletFormScreen), findsOneWidget);
        expect(_fieldText(tester, 'name'), 'BCA Utama');
        expect(repository.listCalls, 1, reason: 'no reload on edit failure');

        await tester.tap(find.byKey(const Key('submit')));
        await tester.pumpAndSettle();
        expect(repository.updated, hasLength(2));
        expect(find.byType(WalletsScreen), findsOneWidget);
      });
    }

    testWidgets('create 400 keeps every field; the second save sends again',
        (tester) async {
      const message = 'Dompet tidak bisa sekaligus utang dan dana dicadangkan.';
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        createResults: [
          const BadRequestException(message: message),
          WalletWrite(wallet: testWallet(id: 31), totals: _totals),
        ],
      );
      await _pump(tester, repository, location: WalletRoutes.create);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      await tester.enterText(find.byKey(const Key('balance')), '1500000');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(_fieldText(tester, 'balance'), '1.500.000');
      expect(repository.listCalls, 1, reason: '400 is certain: no reload');

      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      expect(repository.created, hasLength(2));
      expect(find.byKey(const ValueKey('wallet-31')), findsOneWidget);
    });

    testWidgets('create 502 is treated as uncertain like a network failure',
        (tester) async {
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        createResults: [const ServerException(statusCode: 502)],
      );
      await _pump(tester, repository, location: WalletRoutes.create);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      expect(find.text(kWalletCreateUncertainMessage), findsOneWidget);
      expect(repository.listCalls, 2);
    });

    testWidgets('renaming a legacy negative debt wallet sends only the name',
        (tester) async {
      final legacy = testWallet(
        id: 9,
        name: 'Kartu Lama',
        type: 'credit',
        balance: -1200000,
        isDebt: true,
      );
      final repository = FakeWalletsRepository(
        [
          testWalletList([legacy]),
        ],
        updateResults: [
          WalletWrite(
            wallet: testWallet(
              id: 9,
              name: 'Kartu Baru',
              type: 'credit',
              balance: -1200000,
              isDebt: true,
            ),
            totals: _totals,
          ),
        ],
      );
      await _pump(tester, repository, location: WalletRoutes.edit(9));

      expect(_fieldText(tester, 'balance'), '-1.200.000');
      await tester.enterText(find.byKey(const Key('name')), 'Kartu Baru');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(repository.updated.single.$2, {'name': 'Kartu Baru'});
    });

    testWidgets('a balance correction sends only the balance', (tester) async {
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        updateResults: [
          WalletWrite(
            wallet: testWallet(id: 3, balance: 0),
            totals: _totals,
          ),
        ],
      );
      await _pump(tester, repository, location: WalletRoutes.edit(3));

      await tester.enterText(find.byKey(const Key('balance')), '0');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      expect(repository.updated.single.$2, {'balance': 0});
    });

    testWidgets('a reserve toggle edit moves the row to Dana Dicadangkan',
        (tester) async {
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        updateResults: [
          WalletWrite(
            wallet: testWallet(id: 3, isReserved: true),
            totals: _totals,
          ),
        ],
      );
      await _pump(tester, repository, location: WalletRoutes.edit(3));

      await tester.tap(find.byKey(const Key('reserved')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(repository.updated.single.$2, {'isReserved': true});
      expect(find.byType(WalletsScreen), findsOneWidget);
      // fixture: Tabungan Kurban was the only reserved wallet.
      expect(find.text('DANA DICADANGKAN · 2'), findsOneWidget);
    });

    testWidgets('typing an out-of-range balance shows the integer message',
        (tester) async {
      final repository = FakeWalletsRepository([fixtureWalletList()]);
      await _pump(tester, repository, location: WalletRoutes.create);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      await tester.enterText(find.byKey(const Key('balance')), '99999999999');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      expect(find.text(kWalletBalanceError), findsOneWidget);
      expect(repository.created, isEmpty);
    });

    testWidgets('a lone minus sign is not a number', (tester) async {
      final repository = FakeWalletsRepository([fixtureWalletList()]);
      await _pump(tester, repository, location: WalletRoutes.create);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      await tester.enterText(find.byKey(const Key('balance')), '-');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      expect(find.text(kWalletBalanceError), findsOneWidget);
      expect(repository.created, isEmpty);
    });

    group('pasted decimal', () {
      testWidgets(
        'a pasted decimal amount is not silently multiplied by 100',
        (tester) async {
          final repository = FakeWalletsRepository(
            [fixtureWalletList()],
            createResults: [
              WalletWrite(wallet: testWallet(id: 32), totals: _totals),
            ],
          );
          await _pump(tester, repository, location: WalletRoutes.create);

          await tester.enterText(find.byKey(const Key('name')), 'Dompet');
          await tester.enterText(
            find.byKey(const Key('balance')),
            '1.500.000,50',
          );
          await tester.tap(find.byKey(const Key('submit')));
          await tester.pumpAndSettle();

          // The fraction is dropped, never joined: 1500000, not 150000050.
          expect(repository.created.single.balance, 1500000);
        },
      );
    });

    group('debt wallet of an asset type', () {
      testWidgets(
        'a web-made debt wallet of type "other" shows its current type',
        (tester) async {
          final odd = testWallet(id: 12, name: 'Utang Ibu', type: 'other');
          final debt = Wallet(
            id: odd.id,
            name: odd.name,
            type: 'other',
            balance: 500000,
            displayBalance: -500000,
            isDebt: true,
            isReserved: false,
            description: null,
            sortOrder: 0,
            spentThisMonth: 0,
          );
          await _pump(
            tester,
            FakeWalletsRepository([
              testWalletList([debt]),
            ]),
            location: WalletRoutes.edit(12),
          );
          expect(find.byKey(const Key('type-other')), findsOneWidget);
          expect(
            tester
                .widget<VillageChip>(find.byKey(const Key('type-other')))
                .selected,
            isTrue,
          );
        },
      );
    });
  });
}
