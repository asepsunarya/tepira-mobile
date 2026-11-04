// Independent edge tests for Fase 8 (T20 Riwayat, T21 Ubah/Hapus).
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
import 'package:tepira_mobile/core/wib.dart';
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

/// 2026-11-01 14:00 WIB, the contract's clock.
final _now = DateTime.utc(2026, 11, 1, 7);

final _november = WibMonth(2026, 11);

ExpenseUpdated _updatedWith(Expense expense) {
  final base = expenseUpdatedFromJson(readFixture('mobile_expense_updated'));
  return ExpenseUpdated(
    expense: expense,
    wallets: base.wallets,
    today: base.today,
  );
}

ExpenseDeleted _deleted() =>
    expenseDeletedFromJson(readFixture('mobile_expense_deleted'));

Future<void> _pump(
  WidgetTester tester,
  FakeExpensesRepository expenses, {
  String initialLocation = kHistoryPath,
  DateTime? now,
  Object? initialExtra,
  FakeWalletsRepository? wallets,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initialLocation,
    initialExtra: initialExtra,
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
        walletsRepositoryProvider.overrideWithValue(
          wallets ?? FakeWalletsRepository([fixtureWalletList()]),
        ),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository.budget()),
        lastExpenseWalletStoreProvider
            .overrideWithValue(FakeLastExpenseWalletStore(11)),
        clockProvider.overrideWithValue(() => now ?? _now),
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

Finder get _submit => find.byKey(const Key('expense-submit'));

String _submitLabel(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _submit, matching: find.byType(Text)))
    .data!;

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<VillageButton>(_submit).onPressed != null;

List<List<Object?>> _sent(FakeExpensesRepository expenses) => [
      for (final (id, body) in expenses.updated) [id, body],
    ];

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

bool _nextEnabled(WidgetTester tester) =>
    tester.widget<IconButton>(find.byKey(const Key('month-next'))).onPressed !=
    null;

void main() {
  group('Riwayat month switching', () {
    testWidgets('last second of November WIB is still November',
        (tester) async {
      final repository = FakeExpensesRepository(
        listResults: [testExpenseList(_november, const [])],
      );
      // 2026-11-30 23:59:59 WIB.
      await _pump(
        tester,
        repository,
        now: DateTime.utc(2026, 11, 30, 16, 59, 59),
      );

      expect(repository.listed, [_november]);
      expect(_text(tester, 'history-month'), 'November 2026');
      expect(_nextEnabled(tester), isFalse);
    });

    testWidgets('midnight WIB on 1 December is December, though UTC is Nov',
        (tester) async {
      final december = WibMonth(2026, 12);
      final repository = FakeExpensesRepository(
        listResults: [testExpenseList(december, const [])],
      );
      await _pump(tester, repository, now: DateTime.utc(2026, 11, 30, 17));

      expect(repository.listed, [december]);
      expect(_text(tester, 'history-month'), 'Desember 2026');
      expect(_nextEnabled(tester), isFalse);
    });

    testWidgets('New Year in WIB (31 Dec 17:00 UTC) opens January',
        (tester) async {
      final january = WibMonth(2027, 1);
      final repository = FakeExpensesRepository(
        listResults: [testExpenseList(january, const [])],
      );
      await _pump(tester, repository, now: DateTime.utc(2026, 12, 31, 17));

      expect(repository.listed, [january]);
      expect(_text(tester, 'history-month'), 'Januari 2027');
    });

    testWidgets('next stops at the current month; tapping it loads nothing',
        (tester) async {
      final repository = FakeExpensesRepository(
        listResults: [testExpenseList(_november, const [])],
      );
      await _pump(tester, repository);

      await tester.tap(find.byKey(const Key('month-next')));
      await tester.pumpAndSettle();
      expect(repository.listed, [_november]);
      expect(_text(tester, 'history-month'), 'November 2026');

      // Back three months, then forward again: the arrow disables exactly
      // when the current month is reached.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('month-previous')));
        await tester.pumpAndSettle();
      }
      expect(_text(tester, 'history-month'), 'Agustus 2026');
      for (var i = 0; i < 3; i++) {
        expect(_nextEnabled(tester), isTrue);
        await tester.tap(find.byKey(const Key('month-next')));
        await tester.pumpAndSettle();
      }
      expect(_text(tester, 'history-month'), 'November 2026');
      expect(_nextEnabled(tester), isFalse);
      await tester.tap(find.byKey(const Key('month-next')));
      await tester.pumpAndSettle();
      expect(_text(tester, 'history-month'), 'November 2026');
      expect(
        repository.listed.where((m) => m!.compareTo(_november) > 0),
        isEmpty,
      );
    });

    testWidgets('a month left and opened again is loaded fresh',
        (tester) async {
      final repository = FakeExpensesRepository(
        listResults: [
          fixtureExpenseList(),
          testExpenseList(WibMonth(2026, 10), const []),
          testExpenseList(_november, const []),
        ],
      );
      await _pump(tester, repository);

      await tester.tap(find.byKey(const Key('month-previous')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('month-next')));
      await tester.pumpAndSettle();

      expect(repository.listed, [_november, WibMonth(2026, 10), _november]);
      expect(find.byType(ExpenseRow), findsNothing);
    });
  });

  group('"Menampilkan 500 terbaru"', () {
    testWidgets('not shown when the server sent everything', (tester) async {
      await _pump(
        tester,
        FakeExpensesRepository(listResults: [fixtureExpenseList()]),
      );

      expect(find.byKey(const Key('history-more')), findsNothing);
    });

    testWidgets('stays after a delete; total and count stay server-based',
        (tester) async {
      final list = testExpenseList(
        _november,
        [
          testExpense(id: 499, date: DateTime.utc(2026, 11, 1, 5, 30)),
        ],
        total: 9000000,
        count: 640,
        more: true,
      );
      await _pump(
        tester,
        FakeExpensesRepository(
          listResults: [list],
          deleteResults: [_deleted()],
        ),
      );

      await _openSheet(tester, 499);
      await tester.tap(find.byKey(const Key('expense-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('history-more')), findsOneWidget);
      expect(_text(tester, 'history-total'), 'Rp8.975.000');
      expect(_text(tester, 'history-count'), '639 jajan');
    });
  });

  group('Hapus', () {
    testWidgets('dismissing the dialog by the barrier deletes nothing',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        deleteResults: [_deleted()],
      );
      await _pump(tester, expenses);

      await _openSheet(tester, 499);
      await tester.tap(find.byKey(const Key('expense-delete')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(expenses.deleted, isEmpty);
      expect(find.byKey(const ValueKey('expense-499')), findsOneWidget);
    });

    testWidgets('dismissing the action sheet does nothing', (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
      );
      await _pump(tester, expenses);

      await _openSheet(tester, 499);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(expenses.deleted, isEmpty);
      expect(expenses.updated, isEmpty);
      expect(find.byType(ExpenseEditScreen), findsNothing);
    });

    testWidgets('a double tap on Hapus in the dialog sends one delete',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        deleteResults: [_deleted()],
      )..deleteGate = Completer<void>();
      await _pump(tester, expenses);

      await _openSheet(tester, 499);
      await tester.tap(find.byKey(const Key('expense-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.tap(
        find.byKey(const Key('confirm-delete')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expenses.deleteGate!.complete();
      await tester.pumpAndSettle();

      expect(expenses.deleted, [499]);
    });

    testWidgets('a gateway error keeps the row and shows the message',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        deleteResults: [
          const ServerException(statusCode: 504),
        ],
      );
      await _pump(tester, expenses);

      await _openSheet(tester, 499);
      await tester.tap(find.byKey(const Key('expense-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();

      expect(expenses.deleted, [499]);
      expect(find.byKey(const ValueKey('expense-499')), findsOneWidget);
      expect(_text(tester, 'history-total'), 'Rp50.000');
      expect(find.byType(SnackBar), findsOneWidget);
      // The row can be tapped again after the failure.
      await _openSheet(tester, 499);
      expect(find.byKey(const Key('expense-delete')), findsOneWidget);
    });
  });

  group('Ubah: only changed fields', () {
    testWidgets('several changes send exactly those fields', (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [
          _updatedWith(
            testExpense(
              id: 499,
              amount: 50000,
              category: 'Transport',
              note: 'ojek',
              date: DateTime.utc(2026, 11, 1, 5, 30),
            ),
          ),
        ],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.tap(find.byKey(const Key('expense-chip-50000')));
      await tester.tap(find.byKey(const Key('category-transport')));
      await tester.enterText(find.byKey(const Key('expense-note')), ' ojek ');
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          499,
          {'amount': 50000, 'category': 'Transport', 'note': 'ojek'},
        ],
      ]);
    });

    testWidgets('changing a field and back disables Simpan again',
        (tester) async {
      final expenses =
          FakeExpensesRepository(listResults: [fixtureExpenseList()]);
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      expect(_submitEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('expense-chip-15000')));
      await tester.pump();
      expect(_submitEnabled(tester), isTrue);
      await tester.tap(find.byKey(const Key('expense-chip-25000')));
      await tester.pump();
      expect(_submitLabel(tester), 'Belum ada perubahan');
      expect(_submitEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('day-yesterday')));
      await tester.pump();
      expect(_submitEnabled(tester), isTrue);
      await tester.tap(find.byKey(const Key('day-today')));
      await tester.pump();
      expect(_submitEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('category-makan_harian')));
      await tester.pump();
      expect(_submitEnabled(tester), isTrue);
      await tester.tap(find.byKey(const Key('category-makan_harian')));
      await tester.pump();
      expect(_submitEnabled(tester), isFalse);

      // Only surrounding spaces added: the trimmed note is the same.
      await tester.enterText(
        find.byKey(const Key('expense-note')),
        '  nasi padang  ',
      );
      await tester.pump();
      expect(_submitLabel(tester), 'Belum ada perubahan');
      expect(_submitEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('expense-more')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('source-bonus')));
      await tester.pump();
      expect(_submitEnabled(tester), isTrue);
      await tester.tap(find.byKey(const Key('source-gaji')));
      await tester.pump();
      expect(_submitEnabled(tester), isFalse);
      expect(expenses.updated, isEmpty);
    });

    testWidgets('a note added to a row without one is sent', (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [
          _updatedWith(
            testExpense(
              id: 498,
              amount: 10000,
              category: 'Transport',
              note: 'busway',
              walletId: 9,
              walletName: 'Kartu Kredit',
              date: DateTime.utc(2026, 11, 1, 1, 15),
            ),
          ),
        ],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 498);
      expect(_submitEnabled(tester), isFalse);
      await tester.enterText(find.byKey(const Key('expense-note')), 'busway');
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          498,
          {'note': 'busway'},
        ],
      ]);
    });

    testWidgets('the close button is disabled while saving', (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [
          _updatedWith(
            testExpense(
              id: 499,
              amount: 15000,
              date: DateTime.utc(2026, 11, 1, 5, 30),
            ),
          ),
        ],
      )..updateGate = Completer<void>();
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.tap(find.byKey(const Key('expense-chip-15000')));
      await tester.pump();
      await tester.tap(_submit);
      await tester.pump();
      await tester.tap(find.byKey(const Key('close')), warnIfMissed: false);
      await tester.pump();

      expect(find.byType(ExpenseEditScreen), findsOneWidget);
      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(expenses.updated, hasLength(1));
    });
  });

  group('Ubah: orphan rows', () {
    testWidgets('an orphan row with no wallet picked never sends',
        (tester) async {
      final expenses =
          FakeExpensesRepository(listResults: [fixtureExpenseList()]);
      await _pump(tester, expenses);

      await _openEdit(tester, 497);
      await tester.tap(find.byKey(const Key('expense-chip-50000')));
      await tester.pump();

      expect(_submitLabel(tester), 'Pilih dompet dulu');
      expect(_submitEnabled(tester), isFalse);
      await tester.tap(_submit, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(expenses.updated, isEmpty);
    });

    testWidgets(
        'an orphan row with a picked wallet and a new amount sends both',
        (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [
          _updatedWith(
            testExpense(
              id: 497,
              amount: 50000,
              category: 'Transport',
              note: 'ojek (dompet sudah dihapus)',
              walletId: 11,
              walletName: 'Tunai',
              date: DateTime.utc(2026, 10, 31, 23, 40),
            ),
          ),
        ],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 497);
      await tester.tap(find.byKey(const Key('wallet-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-wallet-11')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expense-chip-50000')));
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          497,
          {'amount': 50000, 'walletId': 11},
        ],
      ]);
      final row = find.byKey(const ValueKey('expense-497'));
      expect(
        find.descendant(
          of: row,
          matching: find.textContaining('Dompet dihapus'),
        ),
        findsNothing,
      );
    });
  });

  group('Ubah: wallet_not_found', () {
    testWidgets('reloads the wallets, drops the pick and keeps the form',
        (tester) async {
      final wallets =
          FakeWalletsRepository([fixtureWalletList(), fixtureWalletList()]);
      final expenses = FakeExpensesRepository(
        listResults: [fixtureExpenseList()],
        updateResults: [
          const BadRequestException(
            code: 'wallet_not_found',
            message: 'Dompet tidak ditemukan. Pilih dompet lain.',
          ),
        ],
      );
      await _pump(tester, expenses, wallets: wallets);

      await _openEdit(tester, 499);
      await tester.tap(find.byKey(const Key('wallet-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-wallet-11')));
      await tester.pumpAndSettle();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          499,
          {'walletId': 11},
        ],
      ]);
      expect(
        find.text('Dompet tidak ditemukan. Pilih dompet lain.'),
        findsOneWidget,
      );
      expect(wallets.listCalls, 2);
      expect(find.byType(ExpenseEditScreen), findsOneWidget);
      expect(_submitLabel(tester), 'Pilih dompet dulu');
      expect(_submitEnabled(tester), isFalse);
    });
  });

  group('Ubah: deep link fallback', () {
    testWidgets('an extra for another id shows the fallback', (tester) async {
      await _pump(
        tester,
        FakeExpensesRepository(listResults: [fixtureExpenseList()]),
        initialLocation: ExpenseRoutes.edit(498),
        initialExtra: fixtureExpenseList().expenses.first, // id 499
      );

      expect(find.byKey(const Key('expense-missing')), findsOneWidget);
      expect(_submit, findsNothing);
    });

    testWidgets('closing the fallback with nothing below opens Riwayat',
        (tester) async {
      final expenses =
          FakeExpensesRepository(listResults: [fixtureExpenseList()]);
      await _pump(
        tester,
        expenses,
        initialLocation: ExpenseRoutes.edit(499),
      );

      await tester.tap(find.byKey(const Key('close')));
      await tester.pumpAndSettle();

      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(expenses.updated, isEmpty);
    });
  });

  group('Ubah: a source the app does not know', () {
    Expense odd() => testExpense(
          id: 499,
          source: 'thr',
          date: DateTime.utc(2026, 11, 1, 5, 30),
        );

    ExpenseList oddList() => testExpenseList(_november, [odd()]);

    testWidgets(
      'opening it shows no change to save',
      (tester) async {
        final expenses = FakeExpensesRepository(listResults: [oddList()]);
        await _pump(tester, expenses);

        await _openEdit(tester, 499);

        expect(_submitLabel(tester), 'Belum ada perubahan');
        expect(_submitEnabled(tester), isFalse);
      },
    );

    testWidgets(
      'changing only the amount does not overwrite the source',
      (tester) async {
        final expenses = FakeExpensesRepository(
          listResults: [oddList()],
          updateResults: [
            _updatedWith(
              testExpense(
                id: 499,
                amount: 15000,
                source: 'thr',
                date: DateTime.utc(2026, 11, 1, 5, 30),
              ),
            ),
          ],
        );
        await _pump(tester, expenses);

        await _openEdit(tester, 499);
        await tester.tap(find.byKey(const Key('expense-chip-15000')));
        await tester.pump();
        await tester.tap(_submit);
        await tester.pumpAndSettle();

        expect(_sent(expenses), [
          [
            499,
            {'amount': 15000},
          ],
        ]);
      },
    );

    testWidgets('opens Lainnya with no source chip selected', (tester) async {
      final expenses = FakeExpensesRepository(listResults: [oddList()]);
      await _pump(tester, expenses);

      await _openEdit(tester, 499);

      for (final wire in ['gaji', 'bonus']) {
        final chip = find.byKey(Key('source-$wire'));
        expect(chip, findsOneWidget);
        expect(tester.widget<VillageChip>(chip).selected, isFalse);
      }
    });

    testWidgets('picking a source sends it', (tester) async {
      final expenses = FakeExpensesRepository(
        listResults: [oddList()],
        updateResults: [
          _updatedWith(
            testExpense(
              id: 499,
              source: 'gaji',
              date: DateTime.utc(2026, 11, 1, 5, 30),
            ),
          ),
        ],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      await tester.tap(find.byKey(const Key('source-gaji')));
      await tester.pump();
      expect(_submitEnabled(tester), isTrue);
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          499,
          {'source': 'gaji'},
        ],
      ]);
    });
  });

  group('Ubah: a bonus row', () {
    testWidgets('changing only the amount sends just the amount',
        (tester) async {
      final bonus = testExpense(
        id: 499,
        source: 'bonus',
        date: DateTime.utc(2026, 11, 1, 5, 30),
      );
      final expenses = FakeExpensesRepository(
        listResults: [
          testExpenseList(_november, [bonus]),
        ],
        updateResults: [
          _updatedWith(
            testExpense(
              id: 499,
              amount: 15000,
              source: 'bonus',
              date: DateTime.utc(2026, 11, 1, 5, 30),
            ),
          ),
        ],
      );
      await _pump(tester, expenses);

      await _openEdit(tester, 499);
      expect(_submitEnabled(tester), isFalse);
      await tester.tap(find.byKey(const Key('expense-chip-15000')));
      await tester.pump();
      await tester.tap(_submit);
      await tester.pumpAndSettle();

      expect(_sent(expenses), [
        [
          499,
          {'amount': 15000},
        ],
      ]);
    });
  });
}
