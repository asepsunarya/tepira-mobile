import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/clock.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/expenses/last_expense_wallet_store.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';
import 'package:tepira_mobile/features/goals/contribute_screen.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_goals_repository.dart';
import '../../helpers/fake_last_expense_wallet_store.dart';
import '../../helpers/fake_wallets_repository.dart';

/// 2026-11-01 14:00 WIB, the contract's clock.
final _now = DateTime.utc(2026, 11, 1, 7);

class _Harness {
  _Harness({
    WalletList? wallets,
    List<Object>? walletResults,
    List<Object>? createResults,
    int? lastWalletId,
    DateTime? now,
  })  : wallets = FakeWalletsRepository(
          walletResults ?? [wallets ?? fixtureWalletList()],
        ),
        expenses = FakeExpensesRepository(
          createResults: createResults ?? [fixtureExpenseCreated()],
        ),
        lastWallet = FakeLastExpenseWalletStore(lastWalletId),
        now = now ?? _now;

  final FakeWalletsRepository wallets;
  final FakeExpensesRepository expenses;
  final FakeLastExpenseWalletStore lastWallet;
  final DateTime now;

  /// Pumps a home page with an "open" button that pushes [location], taps
  /// it, and waits for the Catat screen. The tap is the first of the three
  /// taps of the fastest path.
  Future<void> open(
    WidgetTester tester, {
    String location = ExpenseRoutes.record,
  }) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              key: const Key('open'),
              onPressed: () => context.push(location),
              child: const Text('home'),
            ),
          ),
        ),
        GoRoute(
          path: GoalRoutes.record,
          builder: (context, state) => ContributeScreen(
            goalParam: state.uri.queryParameters[GoalRoutes.recordGoalParam],
            tabParam: state.uri.queryParameters[ExpenseRoutes.tabParam],
          ),
        ),
        GoRoute(
          path: WalletRoutes.create,
          builder: (context, state) => Text('page ${state.uri}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          goalsRepositoryProvider.overrideWithValue(
            FakeGoalsRepository([
              [testGoal()],
            ]),
          ),
          walletsRepositoryProvider.overrideWithValue(wallets),
          expensesRepositoryProvider.overrideWithValue(expenses),
          lastExpenseWalletStoreProvider.overrideWithValue(lastWallet),
          clockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp.router(
          theme: buildVillageTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.runAsync(GoogleFonts.pendingFonts);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }
}

Finder get _submit => find.byKey(const Key('expense-submit'));

String _submitLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: _submit, matching: find.byType(Text)),
    )
    .data!;

String _walletName(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('wallet-name'))).data!;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('three taps: open Catat, a chip, Simpan -> stored once',
      (tester) async {
    final h = _Harness();
    await h.open(tester);

    await _tap(tester, 'expense-chip-25000');
    expect(_submitLabel(tester), 'Simpan Rp25.000');
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    final sent = h.expenses.created.single;
    expect(sent.toJson(), {
      'amount': 25000,
      'walletId': 3,
      'category': null,
      'note': null,
      'source': 'gaji',
    });
    expect(find.text('Jajan Rp25.000 tercatat'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
    expect(h.lastWallet.writes, [3]);
  });

  testWidgets('a double tap on Simpan sends one request', (tester) async {
    final h = _Harness();
    h.expenses.createGate = Completer<void>();
    await h.open(tester);
    await _tap(tester, 'expense-chip-25000');

    await tester.tap(_submit);
    await tester.pump();
    await tester.tap(_submit, warnIfMissed: false);
    await tester.pump();

    expect(_submitLabel(tester), 'Menyimpan…');
    expect(h.expenses.created, hasLength(1));
    h.expenses.createGate!.complete();
    await tester.pumpAndSettle();
    expect(h.expenses.created, hasLength(1));
    expect(find.text('Jajan Rp25.000 tercatat'), findsOneWidget);
  });

  testWidgets('Android back does nothing while Simpan runs', (tester) async {
    final h = _Harness();
    h.expenses.createGate = Completer<void>();
    await h.open(tester);
    await _tap(tester, 'expense-chip-25000');

    await tester.tap(_submit);
    await tester.pump();
    await tester.binding.handlePopRoute();
    // Past any route transition, so a pop would be complete.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.byType(ContributeScreen), findsOneWidget);
    expect(find.text('home'), findsNothing);
    expect(_submitLabel(tester), 'Menyimpan…');
    h.expenses.createGate!.complete();
    await tester.pumpAndSettle();
    expect(h.expenses.created, hasLength(1));
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Android back leaves Catat when nothing runs', (tester) async {
    final h = _Harness();
    await h.open(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(ContributeScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('two taps on Simpan in the same frame send one request',
      (tester) async {
    final h = _Harness();
    h.expenses.createGate = Completer<void>();
    await h.open(tester);
    await _tap(tester, 'expense-chip-25000');

    // No pump between the taps: the second lands before Simpan rebuilds as
    // disabled, so only the in-flight guard can stop it.
    await tester.tap(_submit);
    await tester.tap(_submit, warnIfMissed: false);
    await tester.pump();

    expect(h.expenses.created, hasLength(1));
    h.expenses.createGate!.complete();
    await tester.pumpAndSettle();
    expect(h.expenses.created, hasLength(1));
    expect(find.text('Jajan Rp25.000 tercatat'), findsOneWidget);
  });

  testWidgets('a deduped answer is a plain success', (tester) async {
    final h = _Harness(createResults: [fixtureExpenseDeduped()]);
    await h.open(tester);
    await _tap(tester, 'expense-chip-10000');

    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(find.text('Jajan Rp10.000 tercatat'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
    expect(find.byKey(const Key('expense-error')), findsNothing);
  });

  testWidgets('labels match the artboard: "Nominal" and "DOMPET"',
      (tester) async {
    await _Harness().open(tester);

    expect(find.text('Nominal'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('wallet-picker')),
        matching: find.text('DOMPET'),
      ),
      findsOneWidget,
    );
    expect(find.text('Nominal jajan'), findsNothing);
    expect(find.text('BAYAR DARI DOMPET'), findsNothing);
  });

  group('amount', () {
    testWidgets('0 is refused: Simpan disabled, nothing sent', (tester) async {
      final h = _Harness();
      await h.open(tester);

      expect(_submitLabel(tester), 'Isi nominal dulu');
      await tester.tap(_submit, warnIfMissed: false);
      await tester.pumpAndSettle();
      await _tap(tester, 'key-0');
      await tester.tap(_submit, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_submitLabel(tester), 'Isi nominal dulu');
      expect(h.expenses.created, isEmpty);
    });

    testWidgets('the keypad builds the amount', (tester) async {
      await _Harness().open(tester);

      for (final key in ['2', '5', '000']) {
        await _tap(tester, 'key-$key');
      }

      expect(find.text('25.000'), findsOneWidget);
      expect(_submitLabel(tester), 'Simpan Rp25.000');
    });

    testWidgets('typed or pasted amounts use the Rupiah formatter, positive',
        (tester) async {
      await _Harness().open(tester);
      final field = find.byKey(const Key('expense-amount'));

      await tester.enterText(field, '1.500.000,50');
      await tester.pump();
      expect(find.text('1.500.000'), findsOneWidget);

      await tester.enterText(field, '-25000');
      await tester.pump();
      expect(find.text('25.000'), findsOneWidget);
      expect(_submitLabel(tester), 'Simpan Rp25.000');
    });

    testWidgets('above 100.000.000 shows the server rule, sends nothing',
        (tester) async {
      final h = _Harness();
      await h.open(tester);

      await tester.enterText(
        find.byKey(const Key('expense-amount')),
        '100000001',
      );
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(find.text(kExpenseAmountMessage), findsOneWidget);
      expect(h.expenses.created, isEmpty);
    });

    testWidgets('a paste too long to parse is over the limit, never 0',
        (tester) async {
      final h = _Harness();
      await h.open(tester);

      await tester.enterText(
        find.byKey(const Key('expense-amount')),
        '123456789012345678901234567890',
      );
      await tester.pump();
      expect(_submitLabel(tester), 'Simpan');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(find.text(kExpenseAmountMessage), findsOneWidget);
      expect(h.expenses.created, isEmpty);
    });
  });

  group('wallet default', () {
    testWidgets('no stored wallet -> the first ordinary wallet',
        (tester) async {
      await _Harness().open(tester);

      expect(_walletName(tester), 'BCA');
    });

    testWidgets('the last used wallet is preselected', (tester) async {
      await _Harness(lastWalletId: 11).open(tester);

      expect(_walletName(tester), 'Tunai');
    });

    testWidgets('a reserved last wallet is never the default', (tester) async {
      await _Harness(lastWalletId: 7).open(tester);

      expect(_walletName(tester), 'BCA');
    });

    testWidgets('a debt wallet reads "terutang" and the debt hint',
        (tester) async {
      await _Harness(lastWalletId: 9).open(tester);

      expect(_walletName(tester), 'Kartu Kredit');
      expect(
        find.text('terutang Rp1.200.000 · Jajan menambah utang'),
        findsOneWidget,
      );
    });

    testWidgets('only reserved wallets: no default, but one can be picked',
        (tester) async {
      final h = _Harness(
        wallets: testWalletList([
          testWallet(id: 7, name: 'Tabungan Kurban', isReserved: true),
        ]),
      );
      await h.open(tester);
      await _tap(tester, 'expense-chip-15000');

      expect(_walletName(tester), 'Pilih dompet');
      expect(_submitLabel(tester), 'Pilih dompet dulu');

      await _tap(tester, 'wallet-picker');
      expect(find.byKey(const Key('wallet-section-reserved')), findsOneWidget);
      await _tap(tester, 'pick-wallet-7');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(h.expenses.created.single.walletId, 7);
    });
  });

  testWidgets('the picker lists reserved wallets in their own section',
      (tester) async {
    await _Harness().open(tester);

    await _tap(tester, 'wallet-picker');

    // The field behind the sheet is labelled "DOMPET" too (artboard).
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('DOMPET'),
      ),
      findsOneWidget,
    );
    expect(find.text('KARTU KREDIT & CICILAN'), findsOneWidget);
    expect(find.text('DICADANGKAN'), findsOneWidget);
    final reserved = tester.getTopLeft(find.byKey(const Key('pick-wallet-7')));
    final debt = tester.getTopLeft(find.byKey(const Key('pick-wallet-9')));
    expect(reserved.dy, greaterThan(debt.dy));
    expect(find.text('Dicadangkan · Rp3.000.000'), findsOneWidget);
  });

  testWidgets('no wallets: the form becomes "Buat dompet dulu"',
      (tester) async {
    final h = _Harness(wallets: testWalletList(const []));
    await h.open(tester);

    expect(find.byKey(const Key('expense-submit')), findsNothing);
    await _tap(tester, 'create-wallet');

    expect(find.text('page /wallets/new'), findsOneWidget);
    expect(h.expenses.created, isEmpty);
  });

  testWidgets('wallet list error: retry reloads it', (tester) async {
    final h = _Harness(
      walletResults: [const NetworkException(), fixtureWalletList()],
    );
    await h.open(tester);

    expect(_walletName(tester), 'Daftar dompet gagal dimuat');
    await _tap(tester, 'wallet-picker');

    expect(_walletName(tester), 'BCA');
    expect(h.wallets.listCalls, 2);
  });

  group('fields', () {
    testWidgets('category, note, source and the picked wallet are sent',
        (tester) async {
      final h = _Harness();
      await h.open(tester);

      await _tap(tester, 'expense-chip-50000');
      await _tap(tester, 'category-makan_harian');
      await tester.enterText(find.byKey(const Key('expense-note')), ' bakso ');
      await _tap(tester, 'expense-more');
      await _tap(tester, 'source-bonus');
      await _tap(tester, 'wallet-picker');
      await _tap(tester, 'pick-wallet-9');
      await tester.ensureVisible(_submit);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(h.expenses.created.single.toJson(), {
        'amount': 50000,
        'walletId': 9,
        'category': 'Makan harian',
        'note': 'bakso',
        'source': 'bonus',
      });
    });

    testWidgets('a category tapped twice is cleared', (tester) async {
      final h = _Harness();
      await h.open(tester);

      await _tap(tester, 'expense-chip-10000');
      await _tap(tester, 'category-transport');
      await _tap(tester, 'category-transport');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(h.expenses.created.single.category, isNull);
    });

    testWidgets('"Kemarin" sends the WIB date; "Hari ini" sends none',
        (tester) async {
      final h = _Harness();
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');

      await _tap(tester, 'day-yesterday');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(h.expenses.created.single.day, '2026-10-31');
    });

    testWidgets('just after midnight WIB, "Kemarin" is the WIB yesterday',
        (tester) async {
      // 2026-10-31T17:30Z is 1 Nov 00:30 WIB.
      final h = _Harness(now: DateTime.utc(2026, 10, 31, 17, 30));
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');

      await _tap(tester, 'day-yesterday');
      await _tap(tester, 'day-today');
      await _tap(tester, 'day-yesterday');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(h.expenses.created.single.day, '2026-10-31');
    });
  });

  group('errors', () {
    testWidgets('wallet_not_found reloads the wallets and shows the message',
        (tester) async {
      final h = _Harness(
        createResults: [
          const BadRequestException(
            code: 'wallet_not_found',
            message: 'Dompet tidak ditemukan. Pilih dompet lain.',
          ),
        ],
      );
      await h.open(tester);
      await _tap(tester, 'expense-chip-25000');

      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(
        find.text('Dompet tidak ditemukan. Pilih dompet lain.'),
        findsOneWidget,
      );
      expect(h.wallets.listCalls, 2);
      expect(find.text('home'), findsNothing);
      expect(h.lastWallet.writes, isEmpty);
      expect(_submitLabel(tester), 'Simpan Rp25.000');
    });

    testWidgets('a network error keeps the form for another try',
        (tester) async {
      final h = _Harness(
        createResults: [const NetworkException(), fixtureExpenseCreated()],
      );
      await h.open(tester);
      await _tap(tester, 'expense-chip-25000');

      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(find.text('Koneksi bermasalah. Coba lagi.'), findsOneWidget);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(h.expenses.created, hasLength(2));
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('tabs', () {
    testWidgets('Setor has no wallet field; Jajan does', (tester) async {
      await _Harness().open(tester, location: GoalRoutes.record);

      expect(find.byKey(const Key('wallet-picker')), findsNothing);
      expect(find.byKey(const Key('goal-picker')), findsOneWidget);

      await _tap(tester, 'tab-jajan');

      expect(find.byKey(const Key('wallet-picker')), findsOneWidget);
      expect(find.byKey(const Key('goal-picker')), findsNothing);
    });

    testWidgets('tabs are locked while a jajan is saving', (tester) async {
      final h = _Harness();
      h.expenses.createGate = Completer<void>();
      await h.open(tester);
      await _tap(tester, 'expense-chip-25000');

      await tester.tap(_submit);
      await tester.pump();
      await tester.tap(find.byKey(const Key('tab-setor')));
      await tester.pump();

      expect(find.byKey(const Key('wallet-picker')), findsOneWidget);
      h.expenses.createGate!.complete();
      await tester.pumpAndSettle();
    });
  });
}
