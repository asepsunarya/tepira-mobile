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
import 'package:tepira_mobile/core/widgets/village_button.dart';
import 'package:tepira_mobile/core/widgets/village_chip.dart';
import 'package:tepira_mobile/data/expenses/expense_dto.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/expenses/last_expense_wallet_store.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/expense_edit_screen.dart';
import 'package:tepira_mobile/features/expenses/history_screen.dart';
import 'package:tepira_mobile/features/expenses/model/expense.dart';
import 'package:tepira_mobile/features/expenses/widgets/expense_row.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_last_expense_wallet_store.dart';
import '../../helpers/fake_today_repository.dart';
import '../../helpers/fake_wallets_repository.dart';
import '../../helpers/uncaught_errors.dart';

/// 2026-11-01 14:00 WIB, the contract's clock.
final _now = DateTime.utc(2026, 11, 1, 7);

/// The update fixture's wallets and today, with [expense] as the row.
ExpenseUpdated _updatedWith(Expense expense) {
  final base = expenseUpdatedFromJson(readFixture('mobile_expense_updated'));
  return ExpenseUpdated(
    expense: expense,
    wallets: base.wallets,
    today: base.today,
  );
}

/// Row [id] of the expense fixture.
Expense _listed(int id) =>
    fixtureExpenseList().expenses.firstWhere((e) => e.id == id);

/// [_listed] row 499 with [amount], [note] and [date] replaced.
Expense _row499({int amount = 25000, String? note, DateTime? date}) =>
    testExpense(
      id: 499,
      amount: amount,
      note: note ?? 'nasi padang',
      date: date ?? DateTime.utc(2026, 11, 1, 5, 30),
    );

Future<void> _pump(
  WidgetTester tester,
  FakeExpensesRepository expenses, {
  String initialLocation = kHistoryPath,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: kHistoryPath,
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: GoalRoutes.record,
        builder: (context, state) {
          final raw = state.uri.queryParameters[ExpenseRoutes.expenseParam];
          final id = raw == null ? null : ExpenseRoutes.parseId(raw);
          final extra = state.extra;
          return ExpenseEditScreen(
            expense: extra is Expense && extra.id == id ? extra : null,
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        expensesRepositoryProvider.overrideWithValue(expenses),
        walletsRepositoryProvider
            .overrideWithValue(FakeWalletsRepository([fixtureWalletList()])),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository.budget()),
        lastExpenseWalletStoreProvider
            .overrideWithValue(FakeLastExpenseWalletStore(11)),
        clockProvider.overrideWithValue(() => _now),
      ],
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester, int id) async {
  await tester.tap(find.byKey(ValueKey('expense-$id')));
  await tester.pumpAndSettle();
}

Future<void> _openEdit(WidgetTester tester, int id) async {
  await _openSheet(tester, id);
  await tester.tap(find.byKey(const Key('expense-edit')));
  await tester.pumpAndSettle();
}

Future<void> _confirmDelete(WidgetTester tester, int id) async {
  await _openSheet(tester, id);
  await tester.tap(find.byKey(const Key('expense-delete')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('confirm-delete')));
  await tester.pumpAndSettle();
}

Finder get _submit => find.byKey(const Key('expense-submit'));

String _submitLabel(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _submit, matching: find.byType(Text)))
    .data!;

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<VillageButton>(_submit).onPressed != null;

/// Each update sent, as `[id, body]`, so bodies compare by content.
List<List<Object?>> _sent(FakeExpensesRepository expenses) => [
      for (final (id, body) in expenses.updated) [id, body],
    ];

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('Riwayat row actions', () {
    testWidgets('tapping a row opens Ubah and Hapus', (tester) async {
      await _pump(
        tester,
        FakeExpensesRepository(listResults: [fixtureExpenseList()]),
      );

      await _openSheet(tester, 499);

      expect(find.byKey(const Key('expense-edit')), findsOneWidget);
      expect(find.byKey(const Key('expense-delete')), findsOneWidget);
    });

    testWidgets('Hapus asks first; Batal deletes nothing', (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        deleteResults: [
          expenseDeletedFromJson(readFixture('mobile_expense_deleted')),
        ],
      );
      await _pump(tester, expenses);

      await _openSheet(tester, 499);
      await tester.tap(find.byKey(const Key('expense-delete')));
      await tester.pumpAndSettle();

      expect(find.text('Hapus jajan Rp25.000?'), findsOneWidget);
      expect(expenses.deleted, isEmpty);

      await tester.tap(find.byKey(const Key('cancel-delete')));
      await tester.pumpAndSettle();

      expect(expenses.deleted, isEmpty);
      expect(find.byKey(const ValueKey('expense-499')), findsOneWidget);
    });

    testWidgets('a confirmed delete updates the list from the answer',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        deleteResults: [
          expenseDeletedFromJson(readFixture('mobile_expense_deleted')),
        ],
      );
      await _pump(tester, expenses);

      await _confirmDelete(tester, 499);

      expect(expenses.deleted, [499]);
      expect(expenses.listed, hasLength(1));
      expect(find.byKey(const ValueKey('expense-499')), findsNothing);
      expect(_text(tester, 'history-total'), 'Rp25.000');
      expect(_text(tester, 'history-count'), '2 jajan');
      expect(find.text('Jajan Rp25.000 dihapus'), findsOneWidget);
    });

    testWidgets('the dialog of an orphan row says no balance comes back',
        (tester) async {
      await _pump(
        tester,
        FakeExpensesRepository(listResults: [fixtureExpenseList()]),
      );

      await _openSheet(tester, 497);
      await tester.tap(find.byKey(const Key('expense-delete')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('tidak ada saldo yang dikembalikan'),
        findsOneWidget,
      );
    });

    testWidgets('a row being deleted ignores taps; one delete is sent',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        deleteResults: [
          expenseDeletedFromJson(readFixture('mobile_expense_deleted')),
        ],
      )..deleteGate = Completer<void>();
      await _pump(tester, expenses);

      await _confirmDelete(tester, 499);
      await tester.tap(find.byKey(const ValueKey('expense-499')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('expense-delete')), findsNothing);
      expenses.deleteGate!.complete();
      await tester.pumpAndSettle();
      expect(expenses.deleted, [499]);
    });

    testWidgets('an unexpected delete error frees the row again',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        deleteResults: [
          const FormatException('boom'),
          expenseDeletedFromJson(readFixture('mobile_expense_deleted')),
        ],
      )..deleteGate = Completer<void>();
      await _pump(tester, expenses);

      // The delete runs on from the row tap, so collect from there on.
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _confirmDelete(tester, 499),
      );
      expect(find.byKey(const ValueKey('expense-499')), findsOneWidget);
      expenses.deleteGate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      expect(expenses.deleted, [499]);

      // The row takes taps again, and a second delete is sent.
      await _confirmDelete(tester, 499);
      expect(tester.takeException(), isNull);
      expect(expenses.deleted, [499, 499]);
      expect(find.byKey(const ValueKey('expense-499')), findsNothing);
    });

    testWidgets('a delete of a row already gone says so and reloads',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [
          fixtureExpenseList(),
          testExpenseList(fixtureExpenseList().period, [
            _listed(498),
            _listed(497),
          ]),
        ],
        deleteResults: [const NotFoundException()],
      );
      await _pump(tester, expenses);

      await _confirmDelete(tester, 499);

      expect(find.text('Data tidak ditemukan.'), findsOneWidget);
      expect(expenses.listed, hasLength(2));
      expect(find.byKey(const ValueKey('expense-499')), findsNothing);
    });
  });

  group('Ubah', () {
    testWidgets('opens the Jajan form filled with the expense', (tester) async {
      await _pump(
        tester,
        FakeExpensesRepository(listResults: [fixtureExpenseList()]),
      );

      await _openEdit(tester, 499);

      expect(find.text('Ubah jajan'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('expense-amount')))
            .controller!
            .text,
        '25.000',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('expense-note')))
            .controller!
            .text,
        'nasi padang',
      );
      expect(_text(tester, 'wallet-name'), 'BCA');
      expect(
        tester
            .widget<VillageChip>(find.byKey(const Key('category-makan_harian')))
            .selected,
        isTrue,
      );
      expect(
        tester.widget<VillageChip>(find.byKey(const Key('day-today'))).selected,
        isTrue,
      );
      // Nothing changed yet, so there is nothing to send.
      expect(_submitLabel(tester), 'Belum ada perubahan');
      expect(_submitEnabled(tester), isFalse);
    });

    testWidgets(
        'a web row (key category, spaced note) opens unchanged; '
        'its chip is selected', (tester) async {
      final base = fixtureExpenseList();
      final legacy = testExpense(
        id: 499,
        category: 'transport',
        note: '  nasi padang ',
        date: DateTime.utc(2026, 11, 1, 5, 30),
      );
      final expenses = FakeExpensesRepository(
        listResults: [
          testExpenseList(base.period, [
            for (final e in base.expenses) e.id == 499 ? legacy : e,
          ]),
        ],
        updateResults: [
          _updatedWith(
            testExpense(
              id: 499,
              category: 'Makan harian',
              note: '  nasi padang ',
              date: DateTime.utc(2026, 11, 1, 5, 30),
            ),
          ),
        ],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 499);

      expect(
        tester
            .widget<VillageChip>(find.byKey(const Key('category-transport')))
            .selected,
        isTrue,
      );
      expect(_submitLabel(tester), 'Belum ada perubahan');
      expect(_submitEnabled(tester), isFalse);

      await tester
          .ensureVisible(find.byKey(const Key('category-makan_harian')));
      await tester.tap(find.byKey(const Key('category-makan_harian')));
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          499,
          {'category': 'Makan harian'},
        ],
      ]);
    });

    testWidgets('only the amount changed sends {amount}; the list follows',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [_updatedWith(_row499(amount: 15000))],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.tap(find.byKey(const Key('expense-chip-15000')));
      await tester.pump();
      expect(_submitLabel(tester), 'Simpan perubahan');
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          499,
          {'amount': 15000},
        ],
      ]);
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('Jajan diperbarui'), findsOneWidget);
      final row = find.byKey(const ValueKey('expense-499'));
      expect(
        find.descendant(of: row, matching: find.text('-Rp15.000')),
        findsOneWidget,
      );
      expect(_text(tester, 'history-total'), 'Rp40.000');
      expect(expenses.listed, hasLength(1));
    });

    testWidgets('a cleared note is sent as null', (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [_updatedWith(_row499(note: ''))],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.enterText(find.byKey(const Key('expense-note')), '  ');
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          499,
          {'note': null},
        ],
      ]);
    });

    testWidgets('an unselected category is sent as null', (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [_updatedWith(_row499())],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.tap(find.byKey(const Key('category-makan_harian')));
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          499,
          {'category': null},
        ],
      ]);
    });

    testWidgets('an orphan row needs a wallet before it can be saved',
        (tester) async {
      final orphan = _listed(497);
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [
          _updatedWith(
            testExpense(
              id: 497,
              amount: orphan.amount,
              category: orphan.category,
              note: orphan.note,
              date: orphan.date,
            ),
          ),
        ],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 497);

      // No default, not even the last used wallet (Tunai, id 11).
      expect(_text(tester, 'wallet-name'), 'Pilih dompet');
      expect(_submitLabel(tester), 'Pilih dompet dulu');
      expect(_submitEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('wallet-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-wallet-3')));
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          497,
          {'walletId': 3},
        ],
      ]);
      final row = find.byKey(const ValueKey('expense-497'));
      expect(
        find.descendant(of: row, matching: find.textContaining('BCA')),
        findsOneWidget,
      );
    });

    testWidgets('a day moved into the previous month leaves this month',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [
          _updatedWith(_row499(date: DateTime.utc(2026, 10, 31, 5))),
        ],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.tap(find.byKey(const Key('day-yesterday')));
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          499,
          {'date': '2026-10-31'},
        ],
      ]);
      expect(find.byKey(const ValueKey('expense-499')), findsNothing);
      expect(_text(tester, 'history-total'), 'Rp25.000');
      expect(_text(tester, 'history-count'), '2 jajan');
    });

    testWidgets('a double tap sends one update', (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [_updatedWith(_row499(amount: 15000))],
      )..updateGate = Completer<void>();
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.tap(find.byKey(const Key('expense-chip-15000')));
      await tester.pump();
      await tester.tap(_submit);
      await tester.pump();
      await tester.tap(_submit, warnIfMissed: false);
      await tester.pump();

      expect(_submitLabel(tester), 'Menyimpan…');
      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(expenses.updated, hasLength(1));
    });

    testWidgets('Android back does nothing while the update runs',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [_updatedWith(_row499(amount: 15000))],
      )..updateGate = Completer<void>();
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.tap(find.byKey(const Key('expense-chip-15000')));
      await tester.pump();
      await tester.tap(_submit);
      await tester.pump();

      await tester.binding.handlePopRoute();
      // Past any route transition, so a pop would be complete.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.byType(ExpenseEditScreen), findsOneWidget);
      expect(find.byType(ExpenseRow), findsNothing);
      expect(_submitLabel(tester), 'Menyimpan…');
      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseEditScreen), findsNothing);
      expect(expenses.updated, hasLength(1));
    });

    testWidgets('Android back closes the form when no update runs',
        (tester) async {
      final expenses =
          FakeExpensesRepository(listResults: [fixtureExpenseList()]);
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseEditScreen), findsNothing);
      expect(find.byType(ExpenseRow), findsNWidgets(3));
    });

    testWidgets('a 404 shows the message and keeps the form', (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [const NotFoundException()],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.tap(find.byKey(const Key('expense-chip-15000')));
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_text(tester, 'expense-error'), 'Data tidak ditemukan.');
      expect(find.byType(ExpenseEditScreen), findsOneWidget);
      expect(_submitEnabled(tester), isTrue);
    });

    testWidgets('a link without the listed row points back to Riwayat',
        (tester) async {
      final expenses =
          FakeExpensesRepository(listResults: [fixtureExpenseList()]);
      await _pump(
        tester,
        expenses,
        initialLocation: ExpenseRoutes.edit(499),
      );

      expect(find.byKey(const Key('expense-missing')), findsOneWidget);
      expect(find.byKey(const Key('expense-submit')), findsNothing);

      await tester.tap(find.byKey(const Key('open-history')));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseRow), findsNWidgets(3));
    });
  });

  // PR #25 independent pass: a rejected delete frees the row, and a second
  // delete then succeeds.
  group('Riwayat delete error then success', () {
    testWidgets('a rejected delete, then a retry that succeeds',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        deleteResults: [
          const ApiException('Gagal menghapus'),
          expenseDeletedFromJson(readFixture('mobile_expense_deleted')),
        ],
      );
      await _pump(tester, expenses);

      await _confirmDelete(tester, 499);
      expect(find.text('Gagal menghapus'), findsOneWidget);
      expect(find.byKey(const ValueKey('expense-499')), findsOneWidget);
      expect(expenses.deleted, [499]);

      await _confirmDelete(tester, 499);
      expect(tester.takeException(), isNull);
      expect(expenses.deleted, [499, 499]);
      expect(find.byKey(const ValueKey('expense-499')), findsNothing);
    });
  });
}
