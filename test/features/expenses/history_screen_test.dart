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
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/features/expenses/history_screen.dart';
import 'package:tepira_mobile/features/expenses/widgets/expense_row.dart';

import '../../helpers/fake_expenses_repository.dart';

/// 2026-11-01 14:00 WIB, the contract's clock.
final _now = DateTime.utc(2026, 11, 1, 7);

final _november = WibMonth(2026, 11);
final _october = WibMonth(2026, 10);

Future<void> _pumpRiwayat(
  WidgetTester tester,
  FakeExpensesRepository repository, {
  DateTime? now,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: kHistoryPath,
    routes: [
      GoRoute(
        path: kHistoryPath,
        builder: (context, state) => const HistoryScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        expensesRepositoryProvider.overrideWithValue(repository),
        clockProvider.overrideWithValue(() => now ?? _now),
      ],
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

/// The texts of the day titles and row titles, top to bottom.
List<String> _outline(WidgetTester tester) {
  final texts = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Text),
  );
  return [
    for (final element in texts.evaluate())
      if ((element.widget as Text).data case final data?)
        if (data == data.toUpperCase() && data.contains(RegExp('[A-Z]')) ||
            data.contains(':'))
          data,
  ];
}

void main() {
  testWidgets('shows the skeleton while the month loads', (tester) async {
    final repository =
        FakeExpensesRepository(listResults: [fixtureExpenseList()])
          ..listGate = Completer<void>();
    await _pumpRiwayat(tester, repository, settle: false);

    expect(find.bySemanticsLabel('Memuat riwayat'), findsOneWidget);
    expect(find.byType(ExpenseRow), findsNothing);

    repository.listGate!.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Memuat riwayat'), findsNothing);
    expect(find.byType(ExpenseRow), findsNWidgets(3));
  });

  testWidgets('loads the current WIB month with the server total and count',
      (tester) async {
    final repository =
        FakeExpensesRepository(listResults: [fixtureExpenseList()]);
    await _pumpRiwayat(tester, repository);

    expect(repository.listed, [_november]);
    expect(_text(tester, 'history-month'), 'November 2026');
    expect(_text(tester, 'history-total'), 'Rp50.000');
    expect(_text(tester, 'history-count'), '3 jajan');
    expect(find.byKey(const Key('history-more')), findsNothing);
  });

  testWidgets('a row shows the note, category, wallet and amount',
      (tester) async {
    await _pumpRiwayat(
      tester,
      FakeExpensesRepository(listResults: [fixtureExpenseList()]),
    );

    final row = find.byKey(const ValueKey('expense-499'));
    expect(
      find.descendant(of: row, matching: find.text('nasi padang')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Makan harian · BCA')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('-Rp25.000')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('12:30')),
      findsOneWidget,
    );
    // Without a note the category is the title.
    final noNote = find.byKey(const ValueKey('expense-498'));
    expect(
      find.descendant(of: noNote, matching: find.text('Transport')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: noNote, matching: find.text('Kartu Kredit')),
      findsOneWidget,
    );
  });

  testWidgets('an orphan row says "Dompet dihapus"', (tester) async {
    await _pumpRiwayat(
      tester,
      FakeExpensesRepository(listResults: [fixtureExpenseList()]),
    );

    final orphan = find.byKey(const ValueKey('expense-497'));
    expect(
      find.descendant(
        of: orphan,
        matching: find.text('Transport · Dompet dihapus'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('groups by WIB day across midnight WIB', (tester) async {
    // 2026-11-02 14:00 WIB.
    final now = DateTime.utc(2026, 11, 2, 7);
    final list = testExpenseList(_november, [
      // 00:00 WIB on 2 November.
      testExpense(id: 3, note: 'bubur', date: DateTime.utc(2026, 11, 1, 17)),
      // 23:59 WIB on 1 November.
      testExpense(
        id: 2,
        note: 'martabak',
        date: DateTime.utc(2026, 11, 1, 16, 59),
      ),
      // 00:30 WIB on 1 November, still 31 October in UTC.
      testExpense(
        id: 1,
        note: 'kopi',
        date: DateTime.utc(2026, 10, 31, 17, 30),
      ),
    ]);
    await _pumpRiwayat(
      tester,
      FakeExpensesRepository(listResults: [list]),
      now: now,
    );

    expect(_outline(tester), [
      'DIPAKAI BULAN INI',
      'HARI INI',
      '00:00',
      'KEMARIN',
      '23:59',
      '00:30',
    ]);
  });

  testWidgets('older days show their date', (tester) async {
    final list = testExpenseList(_october, [
      testExpense(id: 1, date: DateTime.utc(2026, 10, 14, 5)),
    ]);
    final repository = FakeExpensesRepository(
      listResults: [fixtureExpenseList(), list],
    );
    await _pumpRiwayat(tester, repository);

    await tester.tap(find.byKey(const Key('month-previous')));
    await tester.pumpAndSettle();

    expect(find.text('14 OKT 2026'), findsOneWidget);
  });

  testWidgets('the arrows switch months; the current month is the last',
      (tester) async {
    final october = testExpenseList(_october, [
      testExpense(id: 400, amount: 12000, date: DateTime.utc(2026, 10, 9, 5)),
    ]);
    final repository = FakeExpensesRepository(
      listResults: [fixtureExpenseList(), october, fixtureExpenseList()],
    );
    await _pumpRiwayat(tester, repository);

    final next = find.byKey(const Key('month-next'));
    expect(tester.widget<IconButton>(next).onPressed, isNull);

    await tester.tap(find.byKey(const Key('month-previous')));
    await tester.pumpAndSettle();

    expect(repository.listed, [_november, _october]);
    expect(_text(tester, 'history-month'), 'Oktober 2026');
    expect(_text(tester, 'history-total'), 'Rp12.000');
    expect(find.byKey(const ValueKey('expense-400')), findsOneWidget);
    expect(tester.widget<IconButton>(next).onPressed, isNotNull);

    await tester.tap(next);
    await tester.pumpAndSettle();

    expect(_text(tester, 'history-month'), 'November 2026');
    expect(find.byType(ExpenseRow), findsNWidgets(3));
  });

  testWidgets('January goes back to December of the year before',
      (tester) async {
    final repository = FakeExpensesRepository(
      listResults: [
        testExpenseList(WibMonth(2027, 1), const []),
        testExpenseList(WibMonth(2026, 12), const []),
      ],
    );
    await _pumpRiwayat(tester, repository, now: DateTime.utc(2027, 1, 5));

    await tester.tap(find.byKey(const Key('month-previous')));
    await tester.pumpAndSettle();

    expect(repository.listed, [WibMonth(2027, 1), WibMonth(2026, 12)]);
    expect(_text(tester, 'history-month'), 'Desember 2026');
  });

  testWidgets('the month follows WIB: 31 Oct 17:00 UTC is November',
      (tester) async {
    final repository = FakeExpensesRepository(
      listResults: [testExpenseList(_november, const [])],
    );
    await _pumpRiwayat(
      tester,
      repository,
      now: DateTime.utc(2026, 10, 31, 17),
    );

    expect(repository.listed, [_november]);
  });

  testWidgets('an empty month says so', (tester) async {
    await _pumpRiwayat(
      tester,
      FakeExpensesRepository(
        listResults: [testExpenseList(_november, const [])],
      ),
    );

    expect(find.byKey(const Key('history-empty')), findsOneWidget);
    expect(find.text('Belum ada jajan bulan ini'), findsOneWidget);
    expect(_text(tester, 'history-total'), 'Rp0');
    expect(find.byType(ExpenseRow), findsNothing);
  });

  testWidgets('more than 500 shows "Menampilkan 500 terbaru"', (tester) async {
    final list = testExpenseList(
      _november,
      [testExpense(date: DateTime.utc(2026, 11, 1, 5))],
      total: 9000000,
      count: 640,
      more: true,
    );
    await _pumpRiwayat(tester, FakeExpensesRepository(listResults: [list]));

    expect(find.text('Menampilkan 500 terbaru'), findsOneWidget);
    expect(_text(tester, 'history-total'), 'Rp9.000.000');
    expect(_text(tester, 'history-count'), '640 jajan');
  });

  testWidgets('an error offers a retry that reloads the month', (tester) async {
    final repository = FakeExpensesRepository(
      listResults: [
        const NetworkException('Tidak ada koneksi internet.'),
        fixtureExpenseList(),
      ],
    );
    await _pumpRiwayat(tester, repository);

    expect(find.byKey(const Key('history-error')), findsOneWidget);
    expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry')));
    await tester.pumpAndSettle();

    expect(repository.listed, [_november, _november]);
    expect(find.byKey(const Key('history-error')), findsNothing);
    expect(find.byType(ExpenseRow), findsNWidgets(3));
  });

  testWidgets('pull to refresh reloads the month', (tester) async {
    final repository = FakeExpensesRepository(
      listResults: [
        fixtureExpenseList(),
        testExpenseList(_november, const []),
      ],
    );
    await _pumpRiwayat(tester, repository);

    await tester.fling(
      find.byType(ListView),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(repository.listed, [_november, _november]);
    expect(find.byKey(const Key('history-empty')), findsOneWidget);
  });
}
