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
import 'package:tepira_mobile/features/goals/contribute_screen.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_goals_repository.dart';
import '../../helpers/fake_last_expense_wallet_store.dart';
import '../../helpers/fake_wallets_repository.dart';

const _notFound = BadRequestException(
  code: 'wallet_not_found',
  message: 'Dompet tidak ditemukan. Pilih dompet lain.',
);

/// The fixture wallets without [id].
WalletList _without(int id) => testWalletList([
      for (final w in fixtureWalletList().wallets)
        if (w.id != id) w,
    ]);

class _Harness {
  _Harness({
    List<Object>? walletResults,
    List<Object>? createResults,
    int? lastWalletId,
    DateTime? now,
  })  : wallets = FakeWalletsRepository(
          walletResults ?? [fixtureWalletList()],
        ),
        expenses = FakeExpensesRepository(
          createResults: createResults ?? [fixtureExpenseCreated()],
        ),
        lastWallet = FakeLastExpenseWalletStore(lastWalletId),
        now = now ?? DateTime.utc(2026, 11, 1, 7);

  final FakeWalletsRepository wallets;
  final FakeExpensesRepository expenses;
  final FakeLastExpenseWalletStore lastWallet;

  /// The clock the form reads; tests move it to cross 00:00 WIB.
  DateTime now;

  Future<void> open(WidgetTester tester) async {
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
              onPressed: () => context.push(ExpenseRoutes.record),
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
    .widget<Text>(find.descendant(of: _submit, matching: find.byType(Text)))
    .data!;

String _walletName(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('wallet-name'))).data!;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.ensureVisible(_submit);
  await tester.tap(_submit);
  await tester.pumpAndSettle();
}

void main() {
  group('double tap', () {
    testWidgets('many taps while saving send one request', (tester) async {
      final h = _Harness();
      h.expenses.createGate = Completer<void>();
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');

      await tester.tap(_submit);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.tap(_submit, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 20));
      }
      // The keypad and chips are locked too, so the amount cannot move.
      await tester.tap(
        find.byKey(const Key('expense-chip-50000')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(h.expenses.created, hasLength(1));
      h.expenses.createGate!.complete();
      await tester.pumpAndSettle();
      expect(h.expenses.created.single.amount, 10000);
      expect(find.text('Jajan Rp10.000 tercatat'), findsOneWidget);
    });

    testWidgets('taps during the Retry-After wait add no request',
        (tester) async {
      final h = _Harness(
        createResults: [
          const ServerException(
            statusCode: 500,
            code: 'server_error',
            retryAfter: Duration(seconds: 1),
          ),
          fixtureExpenseCreated(),
        ],
      );
      await h.open(tester);
      await _tap(tester, 'expense-chip-25000');

      await tester.tap(_submit);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_submit, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_submitLabel(tester), 'Menyimpan…');
      expect(h.expenses.created, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(h.expenses.created, hasLength(2));
      expect(find.text('Jajan Rp25.000 tercatat'), findsOneWidget);
    });
  });

  group('date', () {
    testWidgets('today picked in the date picker sends no date',
        (tester) async {
      final h = _Harness();
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');

      await _tap(tester, 'day-pick');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await _save(tester);

      expect(h.expenses.created.single.day, isNull);
      expect(h.expenses.created.single.toJson().containsKey('date'), isFalse);
    });

    testWidgets('the picker offers today back to 7 WIB days, no future',
        (tester) async {
      // 2026-11-01 00:10 WIB: the UTC date is still 31 Oct.
      final h = _Harness(now: DateTime.utc(2026, 10, 31, 17, 10));
      await h.open(tester);

      await _tap(tester, 'day-pick');
      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );

      expect(
        (dialog.firstDate.year, dialog.firstDate.month, dialog.firstDate.day),
        (2026, 10, 25),
      );
      expect(
        (dialog.lastDate.year, dialog.lastDate.month, dialog.lastDate.day),
        (2026, 11, 1),
      );
    });

    testWidgets('7 days back across the month start is sent as that WIB day',
        (tester) async {
      // 2 Dec 09:00 WIB; 7 days back is 25 Nov.
      final h = _Harness(now: DateTime.utc(2026, 12, 2, 2));
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');

      await _tap(tester, 'day-pick');
      // Switch to text input to type the oldest allowed day.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '11/25/2026');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await _save(tester);

      expect(h.expenses.created.single.day, '2026-11-25');
    });

    testWidgets('"Hari ini" left on across 00:00 WIB still sends no date',
        (tester) async {
      // 30 Nov 23:59 WIB, then 1 Dec 00:01 WIB before Simpan.
      final h = _Harness(now: DateTime.utc(2026, 11, 30, 16, 59));
      await h.open(tester);
      await _tap(tester, 'expense-chip-15000');

      h.now = DateTime.utc(2026, 11, 30, 17, 1);
      await _save(tester);

      expect(h.expenses.created.single.day, isNull);
    });

    testWidgets('"Kemarin" chosen before 00:00 WIB keeps its day after it',
        (tester) async {
      // 1 Nov 23:59 WIB: Kemarin = 31 Oct. After midnight the chosen day is
      // still 31 Oct, now two days back.
      final h = _Harness(now: DateTime.utc(2026, 11, 1, 16, 59));
      await h.open(tester);
      await _tap(tester, 'expense-chip-15000');
      await _tap(tester, 'day-yesterday');

      h.now = DateTime.utc(2026, 11, 1, 17, 1);
      await _save(tester);

      expect(h.expenses.created.single.day, '2026-10-31');
    });

    testWidgets('"Kemarin" on 1 Jan WIB is 31 Dec of the year before',
        (tester) async {
      // 2027-01-01 06:00 WIB = 2026-12-31T23:00Z.
      final h = _Harness(now: DateTime.utc(2026, 12, 31, 23));
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');

      await _tap(tester, 'day-yesterday');
      await _save(tester);

      expect(h.expenses.created.single.day, '2026-12-31');
    });

    testWidgets('"Kemarin" at 06:59 WIB uses the WIB day, not the UTC one',
        (tester) async {
      // 2026-11-02 06:59 WIB = 2026-11-01T23:59Z; Kemarin = 1 Nov.
      final h = _Harness(now: DateTime.utc(2026, 11, 1, 23, 59));
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');

      await _tap(tester, 'day-yesterday');
      await _save(tester);

      expect(h.expenses.created.single.day, '2026-11-01');
    });
  });

  group('wallets', () {
    testWidgets('reserved last wallet with only reserved + debt -> debt',
        (tester) async {
      final h = _Harness(
        walletResults: [
          testWalletList([
            testWallet(id: 7, name: 'Tabungan Kurban', isReserved: true),
            testWallet(
              id: 9,
              name: 'Kartu Kredit',
              type: 'credit',
              balance: 1200000,
              isDebt: true,
            ),
          ]),
        ],
        lastWalletId: 7,
      );
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');
      await _save(tester);

      expect(h.expenses.created.single.walletId, 9);
    });

    testWidgets(
        'only reserved wallets and a stored reserved id: nothing is '
        'sent until one is picked', (tester) async {
      final h = _Harness(
        walletResults: [
          testWalletList([
            testWallet(id: 7, name: 'Tabungan Kurban', isReserved: true),
          ]),
        ],
        lastWalletId: 7,
      );
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');

      expect(_walletName(tester), 'Pilih dompet');
      await tester.tap(_submit, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(h.expenses.created, isEmpty);
    });

    testWidgets(
        'a saved expense from a reserved wallet still stores it as '
        'last, but it is not the next default', (tester) async {
      final h = _Harness();
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');
      await _tap(tester, 'wallet-picker');
      await _tap(tester, 'pick-wallet-7');
      await _save(tester);
      expect(h.expenses.created.single.walletId, 7);

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(_walletName(tester), 'BCA');
    });

    testWidgets(
        'wallet_not_found on the stored wallet: after the reload the '
        'next default is used', (tester) async {
      final h = _Harness(
        walletResults: [fixtureWalletList(), _without(11)],
        createResults: [_notFound, fixtureExpenseCreated()],
        lastWalletId: 11,
      );
      await h.open(tester);
      expect(_walletName(tester), 'Tunai');
      await _tap(tester, 'expense-chip-10000');

      await _save(tester);
      expect(find.text(_notFound.message), findsOneWidget);
      expect(h.wallets.listCalls, 2);
      expect(_walletName(tester), 'BCA');
      await _save(tester);

      expect([for (final e in h.expenses.created) e.walletId], [11, 3]);
    });

    testWidgets('wallet_not_found on a picked wallet drops the pick',
        (tester) async {
      final h = _Harness(
        walletResults: [fixtureWalletList(), _without(9)],
        createResults: [_notFound, fixtureExpenseCreated()],
      );
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');
      await _tap(tester, 'wallet-picker');
      await _tap(tester, 'pick-wallet-9');

      await _save(tester);
      expect(_walletName(tester), 'BCA');
      await _save(tester);

      expect([for (final e in h.expenses.created) e.walletId], [9, 3]);
    });

    testWidgets('wallet_not_found and the reload is empty: "Buat dompet dulu"',
        (tester) async {
      final h = _Harness(
        walletResults: [
          testWalletList([testWallet(id: 3)]),
          testWalletList(const []),
        ],
        createResults: [_notFound],
      );
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');

      await _save(tester);

      expect(find.byKey(const Key('no-wallets')), findsOneWidget);
      expect(h.expenses.created, hasLength(1));
    });

    testWidgets('wallet_not_found: the stored wallet id is not overwritten',
        (tester) async {
      final h = _Harness(
        walletResults: [fixtureWalletList(), _without(3)],
        createResults: [_notFound],
        lastWalletId: 11,
      );
      await h.open(tester);
      await _tap(tester, 'expense-chip-10000');
      await _tap(tester, 'wallet-picker');
      await _tap(tester, 'pick-wallet-3');

      await _save(tester);

      expect(h.lastWallet.writes, isEmpty);
      expect(h.lastWallet.walletId, 11);
    });
  });
}
