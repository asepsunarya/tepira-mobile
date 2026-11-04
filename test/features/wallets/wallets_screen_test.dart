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
import 'package:tepira_mobile/features/wallets/wallets_screen.dart';
import 'package:tepira_mobile/features/wallets/widgets/wallet_row.dart';

import '../../helpers/fake_wallets_repository.dart';

/// Pumps the Dompet screen at `/wallets` with stub pages for the routes it
/// opens.
Future<void> _pumpDompet(
  WidgetTester tester,
  FakeWalletsRepository repository, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: WalletRoutes.list,
    routes: [
      GoRoute(
        path: WalletRoutes.list,
        builder: (context, state) => const WalletsScreen(),
      ),
      for (final path in [WalletRoutes.create, WalletRoutes.editPattern])
        GoRoute(
          path: path,
          builder: (context, state) => Text('page ${state.uri}'),
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
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

/// The text of the group title for [kind], as rendered.
Finder _groupTitle(WalletKind kind, int count) =>
    find.text('${kWalletGroupTitles[kind]!.toUpperCase()} · $count');

void main() {
  testWidgets('shows the skeleton while the wallets load', (tester) async {
    final repository = FakeWalletsRepository([fixtureWalletList()])
      ..listGate = Completer<void>();
    await _pumpDompet(tester, repository, settle: false);

    expect(find.bySemanticsLabel('Memuat dompet'), findsOneWidget);
    expect(find.byType(WalletRow), findsNothing);

    repository.listGate!.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Memuat dompet'), findsNothing);
    expect(find.byType(WalletRow), findsNWidgets(4));
  });

  testWidgets('head shows total saldo, uang bebas, reserved funds and debt',
      (tester) async {
    await _pumpDompet(tester, FakeWalletsRepository([fixtureWalletList()]));

    expect(find.text('TOTAL SALDO'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('total-assets'))).data,
      'Rp11.270.000',
    );
    expect(find.bySemanticsLabel('Uang bebas Rp7.070.000'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Dana dicadangkan Rp3.000.000'),
      findsOneWidget,
    );
    final debts = tester.widget<Text>(find.byKey(const Key('total-debts')));
    expect(debts.data, 'Utang Rp1.200.000');
    expect(debts.style!.color, VillageColors.light.merah);
  });

  testWidgets('lists the three groups in web order with their wallets',
      (tester) async {
    await _pumpDompet(tester, FakeWalletsRepository([fixtureWalletList()]));

    final normal = _groupTitle(WalletKind.normal, 2);
    final reserved = _groupTitle(WalletKind.reserved, 1);
    final debt = _groupTitle(WalletKind.debt, 1);
    expect(normal, findsOneWidget);
    expect(reserved, findsOneWidget);
    expect(debt, findsOneWidget);
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    expect(top(normal), lessThan(top(reserved)));
    expect(top(reserved), lessThan(top(debt)));

    // Server order inside a group: BCA (sortOrder 0) before Tunai.
    expect(
      top(find.byKey(const ValueKey('wallet-3'))),
      lessThan(top(find.byKey(const ValueKey('wallet-11')))),
    );
    // Each wallet sits under its own group.
    double row(int id) => top(find.byKey(ValueKey('wallet-$id')));
    expect(row(11), lessThan(top(reserved)));
    expect(row(7), greaterThan(top(reserved)));
    expect(row(7), lessThan(top(debt)));
    expect(row(9), greaterThan(top(debt)));
  });

  testWidgets('debt shows its display balance negative and red',
      (tester) async {
    await _pumpDompet(tester, FakeWalletsRepository([fixtureWalletList()]));

    final debtBalance = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('wallet-9')),
        matching: find.byKey(const Key('wallet-balance')),
      ),
    );
    expect(debtBalance.data, '-Rp1.200.000');
    expect(debtBalance.style!.color, VillageColors.light.merah);

    final assetBalance = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('wallet-3')),
        matching: find.byKey(const Key('wallet-balance')),
      ),
    );
    expect(assetBalance.data, 'Rp8.250.000');
    expect(assetBalance.style!.color, VillageColors.light.ink);
  });

  testWidgets('hides empty groups', (tester) async {
    await _pumpDompet(
      tester,
      FakeWalletsRepository([
        testWalletList([testWallet(id: 1, name: 'Tunai', type: 'cash')]),
      ]),
    );

    expect(_groupTitle(WalletKind.normal, 1), findsOneWidget);
    expect(find.textContaining('DANA DICADANGKAN ·'), findsNothing);
    expect(find.textContaining('KARTU KREDIT & CICILAN ·'), findsNothing);
  });

  testWidgets('no wallet yet: invites to create the first one', (tester) async {
    await _pumpDompet(tester, FakeWalletsRepository([testWalletList([])]));

    expect(find.text('Buat dompet pertamamu'), findsOneWidget);
    expect(find.byType(WalletRow), findsNothing);
    expect(find.byKey(const Key('add-wallet')), findsNothing);

    await tester.tap(find.byKey(const Key('add-first-wallet')));
    await tester.pumpAndSettle();
    expect(find.text('page /wallets/new'), findsOneWidget);
  });

  testWidgets('a load error offers a retry that reloads', (tester) async {
    final repository = FakeWalletsRepository([
      const NetworkException(),
      fixtureWalletList(),
    ]);
    await _pumpDompet(tester, repository);

    expect(find.text('Peti harta sedang offline'), findsOneWidget);
    expect(find.text('Koneksi bermasalah. Coba lagi.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry')));
    await tester.pumpAndSettle();
    expect(repository.listCalls, 2);
    expect(find.byType(WalletRow), findsNWidgets(4));
  });

  testWidgets('pull down reloads the list', (tester) async {
    final repository = FakeWalletsRepository([
      testWalletList([testWallet(id: 1, name: 'Tunai', type: 'cash')]),
      fixtureWalletList(),
    ]);
    await _pumpDompet(tester, repository);
    expect(find.byType(WalletRow), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(repository.listCalls, 2);
    expect(find.byType(WalletRow), findsNWidgets(4));
  });

  testWidgets('a wallet opens its edit form; the button opens the create form',
      (tester) async {
    await _pumpDompet(tester, FakeWalletsRepository([fixtureWalletList()]));

    await tester.tap(find.byKey(const ValueKey('wallet-7')));
    await tester.pumpAndSettle();
    expect(find.text('page /wallets/7/edit'), findsOneWidget);

    GoRouter.of(tester.element(find.text('page /wallets/7/edit'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-wallet')));
    await tester.pumpAndSettle();
    expect(find.text('page /wallets/new'), findsOneWidget);
  });

  testWidgets('a reserved wallet row says it is reserved', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpDompet(tester, FakeWalletsRepository([fixtureWalletList()]));

    expect(
      find.bySemanticsLabel(
        'Tabungan Kurban, Rekening bank · Dicadangkan · jajan bulan ini Rp0, '
        'saldo Rp3.000.000',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
