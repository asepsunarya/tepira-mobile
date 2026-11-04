import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';
import 'package:tepira_mobile/features/wallets/model/wallet_form_rules.dart';
import 'package:tepira_mobile/features/wallets/wallet_form_screen.dart';
import 'package:tepira_mobile/features/wallets/wallets_screen.dart';

import '../../helpers/fake_wallets_repository.dart';
import '../../helpers/uncaught_errors.dart';

const _newTotals = WalletTotals(
  assets: 16270000,
  debts: 1200000,
  reserved: 8000000,
  netWorth: 15070000,
  free: 7070000,
);

/// Pumps the app's wallet routes, starting at [location] with the Dompet
/// list below it when [location] is a form, as when the form is opened
/// from the list.
Future<GoRouter> _pump(
  WidgetTester tester,
  FakeWalletsRepository repository, {
  String location = WalletRoutes.create,
}) async {
  tester.view.physicalSize = const Size(390, 1800);
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

SwitchListTile _reservedToggle(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byKey(const Key('reserved')));

void main() {
  group('Tambah dompet', () {
    testWidgets('an empty name is refused before anything is sent',
        (tester) async {
      final repository = FakeWalletsRepository([fixtureWalletList()]);
      await _pump(tester, repository);

      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(find.text(kWalletNameError), findsOneWidget);
      expect(repository.created, isEmpty);
    });

    testWidgets('the reserved toggle is off and disabled for a credit card',
        (tester) async {
      await _pump(tester, FakeWalletsRepository([fixtureWalletList()]));

      await tester.tap(find.byKey(const Key('reserved')));
      await tester.pumpAndSettle();
      expect(_reservedToggle(tester).value, isTrue);

      await tester.tap(find.byKey(const Key('type-credit')));
      await tester.pumpAndSettle();

      final toggle = _reservedToggle(tester);
      expect(toggle.value, isFalse);
      expect(toggle.onChanged, isNull);
      expect(find.text('Terutang saat ini'), findsOneWidget);

      await tester.tap(find.byKey(const Key('type-paylater')));
      await tester.pumpAndSettle();
      expect(_reservedToggle(tester).onChanged, isNull);

      await tester.tap(find.byKey(const Key('type-bank')));
      await tester.pumpAndSettle();
      expect(_reservedToggle(tester).onChanged, isNotNull);
      expect(find.text('Saldo awal'), findsOneWidget);
    });

    testWidgets('a negative amount owed is refused', (tester) async {
      final repository = FakeWalletsRepository([fixtureWalletList()]);
      await _pump(tester, repository);

      await tester.enterText(find.byKey(const Key('name')), 'Kartu Kredit');
      await tester.tap(find.byKey(const Key('type-credit')));
      await tester.enterText(find.byKey(const Key('balance')), '-5000');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(find.text(kWalletDebtNegativeError), findsOneWidget);
      expect(repository.created, isEmpty);
    });

    testWidgets(
        'saving calls the repository once, returns to Dompet and shows the '
        'new wallet and totals from the answer', (tester) async {
      final created = testWallet(
        id: 20,
        name: 'BCA',
        type: 'bank',
        balance: 5000000,
        isReserved: true,
        description: 'Haji',
        sortOrder: 4,
      );
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        createResults: [WalletWrite(wallet: created, totals: _newTotals)],
      )..writeGate = Completer<void>();
      await _pump(tester, repository);

      await tester.tap(find.byKey(const Key('brand-BCA')));
      await tester.tap(find.byKey(const Key('type-bank')));
      await tester.enterText(find.byKey(const Key('balance')), '5000000');
      await tester.enterText(find.byKey(const Key('description')), ' Haji ');
      await tester.tap(find.byKey(const Key('reserved')));
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('name')))
            .controller!
            .text,
        'BCA',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('balance')))
            .controller!
            .text,
        '5.000.000',
      );

      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      expect(repository.created, hasLength(1));
      expect(repository.created.single.toJson(), {
        'name': 'BCA',
        'type': 'bank',
        'balance': 5000000,
        'isDebt': false,
        'isReserved': true,
        'description': 'Haji',
      });

      repository.writeGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(WalletsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-20')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('total-assets'))).data,
        'Rp16.270.000',
      );
      expect(
        find.bySemanticsLabel('Dana dicadangkan Rp8.000.000'),
        findsOneWidget,
      );
      expect(repository.listCalls, 1, reason: 'updated from the answer');
    });

    testWidgets('a credit card is created as debt', (tester) async {
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        createResults: [
          WalletWrite(
            wallet: testWallet(id: 21, type: 'credit', isDebt: true),
            totals: _newTotals,
          ),
        ],
      );
      await _pump(tester, repository);

      await tester.enterText(find.byKey(const Key('name')), 'Kartu BNI');
      await tester.tap(find.byKey(const Key('type-credit')));
      await tester.enterText(find.byKey(const Key('balance')), '750000');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      final sent = repository.created.single;
      expect(sent.isDebt, isTrue);
      expect(sent.isReserved, isFalse);
      expect(sent.balance, 750000);
    });

    testWidgets('a server validation message is shown as is', (tester) async {
      const message = 'Jenis dompet tidak dikenal.';
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        createResults: [const BadRequestException(message: message)],
      );
      await _pump(tester, repository);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(find.byType(WalletFormScreen), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('submitError'))).data,
        message,
      );
    });

    testWidgets('an unexpected save error leaves the form usable',
        (tester) async {
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        createResults: [
          const FormatException('boom'),
          WalletWrite(wallet: testWallet(id: 22), totals: _newTotals),
        ],
      )..writeGate = Completer<void>();
      await _pump(tester, repository);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      final errors = <Object>[];
      await collectUncaught(
        errors,
        () => tester.tap(find.byKey(const Key('submit'))),
      );
      await tester.pump();
      expect(find.text('Menyimpan…'), findsOneWidget);

      repository.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      expect(find.byType(WalletFormScreen), findsOneWidget);
      expect(find.text('Menyimpan…'), findsNothing);
      expect(find.text('Simpan dompet'), findsOneWidget);

      // A second Simpan is sent and succeeds.
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repository.created, hasLength(2));
      expect(find.byType(WalletFormScreen), findsNothing);
    });

    testWidgets('a pasted decimal amount drops the fraction, not the comma',
        (tester) async {
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        createResults: [
          WalletWrite(wallet: testWallet(id: 22), totals: _newTotals),
        ],
      );
      await _pump(tester, repository);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      await tester.enterText(find.byKey(const Key('balance')), '1.500.000,50');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('balance')))
            .controller!
            .text,
        '1.500.000',
      );
      await tester.enterText(find.byKey(const Key('balance')), 'Rp-25.000,-');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('balance')))
            .controller!
            .text,
        '25.000',
        reason: 'the sign only counts as the first character',
      );
      await tester.enterText(find.byKey(const Key('balance')), '1.500.000,50');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(repository.created.single.balance, 1500000);
    });

    testWidgets('a description with a NUL character is refused before sending',
        (tester) async {
      final repository = FakeWalletsRepository([fixtureWalletList()]);
      await _pump(tester, repository);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      await tester.enterText(
        find.byKey(const Key('description')),
        'Kurban\u00002027',
      );
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(find.text(kWalletDescriptionError), findsOneWidget);
      expect(repository.created, isEmpty);
    });

    testWidgets('a network failure says the wallet may already be stored',
        (tester) async {
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        createResults: [const NetworkException()],
      );
      await _pump(tester, repository);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(find.text(kWalletCreateUncertainMessage), findsOneWidget);
      expect(repository.listCalls, 2, reason: 'the list is reloaded');
    });
  });

  group('Ubah dompet', () {
    testWidgets('sends only the changed name and refreshes from the answer',
        (tester) async {
      final list = fixtureWalletList();
      final bca = list.wallets.firstWhere((w) => w.id == 3);
      final renamed = testWallet(
        id: 3,
        name: 'BCA Utama',
        balance: bca.balance,
        spentThisMonth: bca.spentThisMonth,
      );
      final repository = FakeWalletsRepository(
        [list],
        updateResults: [WalletWrite(wallet: renamed, totals: _newTotals)],
      );
      await _pump(tester, repository, location: WalletRoutes.edit(3));

      expect(find.text('Ubah dompet'), findsOneWidget);
      expect(find.text('Saldo saat ini'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('balance')))
            .controller!
            .text,
        '8.250.000',
      );

      await tester.enterText(find.byKey(const Key('name')), 'BCA Utama');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(repository.updated.single.$1, 3);
      expect(repository.updated.single.$2, {'name': 'BCA Utama'});
      expect(find.byType(WalletsScreen), findsOneWidget);
      expect(find.text('BCA Utama'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('total-assets'))).data,
        'Rp16.270.000',
      );
      expect(repository.listCalls, 1);
    });

    testWidgets('nothing changed: returns without a request', (tester) async {
      final repository = FakeWalletsRepository([fixtureWalletList()]);
      await _pump(tester, repository, location: WalletRoutes.edit(7));

      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(repository.updated, isEmpty);
      expect(find.byType(WalletsScreen), findsOneWidget);
    });

    testWidgets('a reserved wallet can be released', (tester) async {
      final list = fixtureWalletList();
      final kurban = list.wallets.firstWhere((w) => w.id == 7);
      final repository = FakeWalletsRepository(
        [list],
        updateResults: [
          WalletWrite(
            wallet: testWallet(id: 7, name: kurban.name, balance: 3000000),
            totals: _newTotals,
          ),
        ],
      );
      await _pump(tester, repository, location: WalletRoutes.edit(7));
      expect(_reservedToggle(tester).value, isTrue);

      await tester.tap(find.byKey(const Key('reserved')));
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();

      expect(repository.updated.single.$1, 7);
      expect(repository.updated.single.$2, {'isReserved': false});
    });

    testWidgets('a debt wallet may change type but cannot be reserved',
        (tester) async {
      final repository = FakeWalletsRepository(
        [fixtureWalletList()],
        updateResults: [
          WalletWrite(
            wallet: testWallet(id: 9, type: 'cash', isDebt: true),
            totals: _newTotals,
          ),
        ],
      );
      await _pump(tester, repository, location: WalletRoutes.edit(9));

      expect(find.byKey(const Key('type-credit')), findsOneWidget);
      expect(find.byKey(const Key('type-paylater')), findsOneWidget);
      expect(find.byKey(const Key('type-bank')), findsOneWidget);
      expect(find.text('Terutang saat ini'), findsOneWidget);
      expect(_reservedToggle(tester).onChanged, isNull);

      await tester.tap(find.byKey(const Key('type-cash')));
      await tester.pumpAndSettle();
      expect(find.text('Terutang saat ini'), findsOneWidget);
      expect(_reservedToggle(tester).onChanged, isNull);

      await tester.tap(find.byKey(const Key('submit')));
      await tester.pumpAndSettle();
      expect(repository.updated.single.$2, {'type': 'cash'});
    });

    testWidgets('an asset wallet cannot become debt', (tester) async {
      await _pump(
        tester,
        FakeWalletsRepository([fixtureWalletList()]),
        location: WalletRoutes.edit(3),
      );

      expect(find.byKey(const Key('type-credit')), findsNothing);
      expect(find.byKey(const Key('type-paylater')), findsNothing);
      expect(find.byKey(const Key('type-cash')), findsOneWidget);
    });

    testWidgets('an unknown or invalid wallet id says it is not found',
        (tester) async {
      final repository = FakeWalletsRepository([fixtureWalletList()]);
      final router = await _pump(
        tester,
        repository,
        location: WalletRoutes.edit(404),
      );
      expect(find.text(kWalletNotFoundMessage), findsOneWidget);

      router.go('/wallets/abc/edit');
      await tester.pumpAndSettle();
      expect(find.text(kWalletNotFoundMessage), findsOneWidget);
      expect(find.byKey(const Key('submit')), findsNothing);
    });

    testWidgets('a list that fails to load offers a retry', (tester) async {
      final repository = FakeWalletsRepository([
        const ServerException(),
        fixtureWalletList(),
      ]);
      final router = GoRouter(
        initialLocation: WalletRoutes.edit(3),
        routes: [
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
          child: MaterialApp.router(
            theme: buildVillageTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.runAsync(GoogleFonts.pendingFonts);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('retry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('submit')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('name')))
            .controller!
            .text,
        'BCA',
      );
    });
  });
}
