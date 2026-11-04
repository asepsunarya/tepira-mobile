// Edge cases for the CP4 follow-ups: Android back (PopScope) while a save
// runs on Setor, Jajan and the expense edit form, and the legacy-row
// "unchanged" detection of the edit form, and recovery from an
// unexpected (non-AppException) save error.
//
// Every screen is opened on top of a '/' -> '/mid' stack, so a save that
// pops twice would land on '/' instead of '/mid'.
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
import 'package:tepira_mobile/core/unexpected_error.dart';
import 'package:tepira_mobile/core/widgets/village_button.dart';
import 'package:tepira_mobile/core/widgets/village_chip.dart';
import 'package:tepira_mobile/data/expenses/expense_dto.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/expenses/last_expense_wallet_store.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/expense_edit_screen.dart';
import 'package:tepira_mobile/features/expenses/model/expense.dart';
import 'package:tepira_mobile/features/goals/contribute_screen.dart';

import '../helpers/fake_expenses_repository.dart';
import '../helpers/fake_goals_repository.dart';
import '../helpers/fake_last_expense_wallet_store.dart';
import '../helpers/fake_today_repository.dart';
import '../helpers/fake_wallets_repository.dart';
import '../helpers/uncaught_errors.dart';

/// 2026-11-01 14:00 WIB, the contract's clock.
final _now = DateTime.utc(2026, 11, 1, 7);

/// Goals fake whose [contribute] is gated and may throw per call.
class _Goals extends FakeGoalsRepository {
  _Goals({this.errors = const []})
      : super([
          [testGoal()],
        ]);

  final List<Exception?> errors;
  final List<int> amounts = [];
  Completer<void>? gate;

  @override
  Future<void> contribute(int goalId, int amount, [String? note]) async {
    final call = amounts.length;
    amounts.add(amount);
    await gate?.future;
    final error = call < errors.length ? errors[call] : null;
    if (error != null) throw error;
  }
}

ExpenseUpdated _updatedWith(Expense expense) {
  final base = expenseUpdatedFromJson(readFixture('mobile_expense_updated'));
  return ExpenseUpdated(
    expense: expense,
    wallets: base.wallets,
    today: base.today,
  );
}

Expense _row({
  int amount = 25000,
  String? category = 'Makan harian',
  String? note = 'nasi padang',
}) =>
    testExpense(
      id: 499,
      amount: amount,
      category: category,
      note: note,
      date: DateTime.utc(2026, 11, 1, 5, 30),
    );

Future<void> _pump(
  WidgetTester tester, {
  required String location,
  Object? extra,
  _Goals? goals,
  FakeExpensesRepository? expenses,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('root')),
      ),
      GoRoute(
        path: '/mid',
        builder: (context, state) => const Scaffold(body: Text('mid')),
      ),
      GoRoute(
        path: GoalRoutes.detailPattern,
        builder: (context, state) => Scaffold(body: Text('goal ${state.uri}')),
      ),
      GoRoute(
        path: kHistoryPath,
        builder: (context, state) => const Scaffold(body: Text('history')),
      ),
      GoRoute(
        path: GoalRoutes.record,
        builder: (context, state) {
          final query = state.uri.queryParameters;
          if (query.containsKey(ExpenseRoutes.expenseParam)) {
            final extra = state.extra;
            return ExpenseEditScreen(expense: extra is Expense ? extra : null);
          }
          return ContributeScreen(
            goalParam: query[GoalRoutes.recordGoalParam],
            tabParam: query[ExpenseRoutes.tabParam],
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        goalsRepositoryProvider.overrideWithValue(goals ?? _Goals()),
        expensesRepositoryProvider.overrideWithValue(
          expenses ??
              FakeExpensesRepository(createResults: [fixtureExpenseCreated()]),
        ),
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
  unawaited(router.push('/mid'));
  await tester.pumpAndSettle();
  unawaited(router.push(location, extra: extra));
  await tester.pumpAndSettle();
}

/// Sends Android back and lets any route transition finish.
Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pump();
}

/// The generic error is shown inline in the form's error line ([errorKey]),
/// not in a snackbar, so the bottom-docked Simpan ([submitKey]) stays
/// uncovered and can be tapped straight away.
void _expectInlineUnexpected(
  WidgetTester tester, {
  required Key errorKey,
  required Key submitKey,
}) {
  expect(
    tester.widget<Text>(find.byKey(errorKey)).data,
    kUnexpectedErrorMessage,
  );
  expect(find.text(kUnexpectedErrorMessage), findsOneWidget);
  expect(find.byType(SnackBar), findsNothing);
  expect(find.byKey(submitKey).hitTestable(), findsOneWidget);
}

final _expenseSubmit = find.byKey(const Key('expense-submit'));

String _expenseLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: _expenseSubmit, matching: find.byType(Text)),
    )
    .data!;

bool _expenseEnabled(WidgetTester tester) =>
    tester.widget<VillageButton>(_expenseSubmit).onPressed != null;

void _expectOnMid(WidgetTester tester) {
  expect(find.text('mid'), findsOneWidget);
  expect(find.text('root'), findsNothing);
  expect(find.byType(ContributeScreen), findsNothing);
  expect(find.byType(ExpenseEditScreen), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  group('Setor: back during a deposit', () {
    testWidgets('blocked while running; success pops exactly once',
        (tester) async {
      final goals = _Goals()..gate = Completer<void>();
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      await _tap(tester, const Key('submit'));
      await _back(tester);

      expect(find.byType(ContributeScreen), findsOneWidget);
      expect(goals.amounts, [20000]);

      goals.gate!.complete();
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(goals.amounts, [20000]);
    });

    testWidgets('a rejected deposit re-enables back', (tester) async {
      final goals = _Goals(errors: [const ApiException('Nominal tidak valid')])
        ..gate = Completer<void>();
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      await _tap(tester, const Key('submit'));
      await _back(tester);
      expect(find.byType(ContributeScreen), findsOneWidget);

      goals.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ContributeScreen), findsOneWidget);
      expect(find.text('Nominal tidak valid'), findsOneWidget);

      await _back(tester);
      await tester.pumpAndSettle();
      _expectOnMid(tester);
    });

    testWidgets('an uncertain (network) deposit re-enables back',
        (tester) async {
      final goals = _Goals(errors: [const NetworkException()])
        ..gate = Completer<void>();
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      await _tap(tester, const Key('submit'));
      await _back(tester);
      expect(find.byType(ContributeScreen), findsOneWidget);

      goals.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ContributeScreen), findsOneWidget);

      await _back(tester);
      await tester.pumpAndSettle();
      _expectOnMid(tester);
    });
  });

  group('Jajan tab: back during Simpan', () {
    testWidgets('a failed save re-enables back', (tester) async {
      final expenses = FakeExpensesRepository(
        createResults: [const ApiException('Gagal menyimpan')],
      )..createGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.record,
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-25000'));
      await _tap(tester, const Key('expense-submit'));
      await _back(tester);
      expect(find.byType(ContributeScreen), findsOneWidget);
      expect(_expenseLabel(tester), 'Menyimpan…');

      expenses.createGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ContributeScreen), findsOneWidget);
      expect(find.text('Gagal menyimpan'), findsOneWidget);

      await _back(tester);
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.created, hasLength(1));
    });

    testWidgets('success after a blocked back pops exactly once',
        (tester) async {
      final expenses =
          FakeExpensesRepository(createResults: [fixtureExpenseCreated()])
            ..createGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.record,
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-25000'));
      await _tap(tester, const Key('expense-submit'));
      await _back(tester);
      await _back(tester);
      expect(find.byType(ContributeScreen), findsOneWidget);

      expenses.createGate!.complete();
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.created, hasLength(1));
    });
  });

  group('Edit form: back during the update', () {
    testWidgets('a failed update re-enables back', (tester) async {
      final row = _row();
      final expenses = FakeExpensesRepository(
        updateResults: [const NotFoundException()],
      )..updateGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.edit(499),
        extra: row,
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-15000'));
      await _tap(tester, const Key('expense-submit'));
      await _back(tester);
      expect(find.byType(ExpenseEditScreen), findsOneWidget);

      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Data tidak ditemukan.'), findsOneWidget);
      expect(find.byType(ExpenseEditScreen), findsOneWidget);

      await _back(tester);
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.updated, hasLength(1));
    });

    testWidgets('success after a blocked back pops exactly once',
        (tester) async {
      final expenses = FakeExpensesRepository(
        updateResults: [_updatedWith(_row(amount: 15000))],
      )..updateGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.edit(499),
        extra: _row(),
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-15000'));
      await _tap(tester, const Key('expense-submit'));
      await _back(tester);
      await _back(tester);
      expect(find.byType(ExpenseEditScreen), findsOneWidget);

      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.updated, hasLength(1));
    });
  });

  group('Edit form: legacy rows', () {
    Future<FakeExpensesRepository> open(
      WidgetTester tester,
      Expense row,
    ) async {
      final expenses = FakeExpensesRepository(
        updateResults: [_updatedWith(row)],
      );
      await _pump(
        tester,
        location: ExpenseRoutes.edit(row.id),
        extra: row,
        expenses: expenses,
      );
      return expenses;
    }

    bool selected(WidgetTester tester, String key) =>
        tester.widget<VillageChip>(find.byKey(Key('category-$key'))).selected;

    testWidgets('legacy key + changed amount sends only {amount}',
        (tester) async {
      final expenses = await open(tester, _row(category: 'transport'));

      expect(selected(tester, 'transport'), isTrue);
      await _tap(tester, const Key('expense-chip-15000'));
      expect(_expenseEnabled(tester), isTrue);
      await _tap(tester, const Key('expense-submit'));
      await tester.pumpAndSettle();

      expect(expenses.updated.single.$2, {'amount': 15000});
    });

    testWidgets('legacy key, tapping its own chip off sends category null',
        (tester) async {
      final expenses = await open(tester, _row(category: 'transport'));

      await _tap(tester, const Key('category-transport'));
      expect(selected(tester, 'transport'), isFalse);
      await _tap(tester, const Key('expense-submit'));
      await tester.pumpAndSettle();

      expect(expenses.updated.single.$2, {'category': null});
    });

    testWidgets('unknown category opens unchanged with no chip selected',
        (tester) async {
      final expenses = await open(tester, _row(category: 'Lain-lain'));

      expect(_expenseLabel(tester), 'Belum ada perubahan');
      expect(_expenseEnabled(tester), isFalse);
      final chips = tester
          .widgetList<VillageChip>(
            find.byWidgetPredicate(
              (w) =>
                  w is VillageChip &&
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('category-'),
            ),
          )
          .toList();
      expect(chips, isNotEmpty);
      expect(chips.where((c) => c.selected), isEmpty);

      await _tap(tester, const Key('category-kesehatan'));
      await _tap(tester, const Key('expense-submit'));
      await tester.pumpAndSettle();
      expect(expenses.updated.single.$2, {'category': 'Kesehatan / Obat'});
    });

    testWidgets('whitespace-only stored note opens unchanged', (tester) async {
      await open(tester, _row(note: '   '));

      expect(_expenseLabel(tester), 'Belum ada perubahan');
      expect(_expenseEnabled(tester), isFalse);
    });

    testWidgets('null stored note + typing only spaces stays unchanged',
        (tester) async {
      final expenses = await open(tester, _row(note: null));

      await tester.ensureVisible(find.byKey(const Key('expense-note')));
      await tester.enterText(find.byKey(const Key('expense-note')), '   ');
      await tester.pump();
      expect(_expenseLabel(tester), 'Belum ada perubahan');
      expect(_expenseEnabled(tester), isFalse);
      expect(expenses.updated, isEmpty);
    });

    testWidgets('null stored note + real text sends the trimmed note',
        (tester) async {
      final expenses = await open(tester, _row(note: null));

      await tester.ensureVisible(find.byKey(const Key('expense-note')));
      await tester.enterText(find.byKey(const Key('expense-note')), '  soto ');
      await tester.pump();
      await _tap(tester, const Key('expense-submit'));
      await tester.pumpAndSettle();
      expect(expenses.updated.single.$2, {'note': 'soto'});
    });
  });

  // A failure that is not an AppException (a bug, a parse error) is not
  // handled by the save flows, but it must still unblock the screen: the
  // saving flag is reset in a `finally`, so back and Simpan work again.
  group('Unexpected (non-AppException) save errors', () {
    testWidgets('Setor recovers: back and Simpan work again', (tester) async {
      final goals = _Goals(errors: [const FormatException('boom')])
        ..gate = Completer<void>();
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _tap(tester, const Key('submit')),
      );
      await _back(tester);
      expect(find.byType(ContributeScreen), findsOneWidget);

      goals.gate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      expect(find.text(kUnexpectedErrorMessage), findsOneWidget);
      expect(find.byType(ContributeScreen), findsOneWidget);
      expect(find.text('Menyimpan…'), findsNothing);
      expect(
        tester.widget<VillageButton>(find.byKey(const Key('submit'))).onPressed,
        isNotNull,
      );

      await _back(tester);
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(goals.amounts, [20000]);
    });

    testWidgets('Jajan recovers: back and Simpan work again', (tester) async {
      final expenses = FakeExpensesRepository(
        createResults: [const FormatException('boom'), fixtureExpenseCreated()],
      )..createGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.record,
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-25000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _tap(tester, const Key('expense-submit')),
      );
      await _back(tester);
      expect(_expenseLabel(tester), 'Menyimpan…');

      expenses.createGate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      expect(find.text(kUnexpectedErrorMessage), findsOneWidget);
      expect(find.byType(ContributeScreen), findsOneWidget);
      expect(_expenseLabel(tester), isNot('Menyimpan…'));
      expect(_expenseEnabled(tester), isTrue);

      // A second Simpan is sent at once and succeeds.
      await _tap(tester, const Key('expense-submit'));
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.created, hasLength(2));
    });

    testWidgets('the edit form recovers: back works again', (tester) async {
      final expenses = FakeExpensesRepository(
        updateResults: [const FormatException('boom')],
      )..updateGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.edit(499),
        extra: _row(),
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-15000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _tap(tester, const Key('expense-submit')),
      );
      await _back(tester);
      expect(find.byType(ExpenseEditScreen), findsOneWidget);

      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      expect(find.text(kUnexpectedErrorMessage), findsOneWidget);
      expect(find.byType(ExpenseEditScreen), findsOneWidget);
      expect(_expenseLabel(tester), isNot('Menyimpan…'));
      expect(_expenseEnabled(tester), isTrue);

      await _back(tester);
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.updated, hasLength(1));
    });
  });

  // The generic error sits in the form's own error line above the
  // bottom-docked Simpan, never in a snackbar over it, and goes away on the
  // next edit or submit like the form's other save errors.
  group('Unexpected save errors are shown inline', () {
    testWidgets('Setor: inline, Simpan uncovered, cleared by an edit',
        (tester) async {
      final goals = _Goals(errors: [const FormatException('boom')])
        ..gate = Completer<void>();
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _tap(tester, const Key('submit')),
      );
      goals.gate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      _expectInlineUnexpected(
        tester,
        errorKey: const Key('submit-error'),
        submitKey: const Key('submit'),
      );

      await _tap(tester, const Key('chip-50000'));
      expect(find.byKey(const Key('submit-error')), findsNothing);
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
    });

    testWidgets('Jajan: inline, Simpan uncovered, cleared by an edit',
        (tester) async {
      final expenses = FakeExpensesRepository(
        createResults: [const FormatException('boom')],
      )..createGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.record,
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-25000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _tap(tester, const Key('expense-submit')),
      );
      expenses.createGate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      _expectInlineUnexpected(
        tester,
        errorKey: const Key('expense-error'),
        submitKey: const Key('expense-submit'),
      );

      await _tap(tester, const Key('expense-chip-15000'));
      expect(find.byKey(const Key('expense-error')), findsNothing);
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
    });

    testWidgets('the edit form: inline, cleared by the next submit',
        (tester) async {
      final expenses = FakeExpensesRepository(
        updateResults: [
          const FormatException('boom'),
          _updatedWith(_row(amount: 15000)),
        ],
      )..updateGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.edit(499),
        extra: _row(),
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-15000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _tap(tester, const Key('expense-submit')),
      );
      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      _expectInlineUnexpected(
        tester,
        errorKey: const Key('expense-error'),
        submitKey: const Key('expense-submit'),
      );

      expenses.updateGate = Completer<void>();
      await _tap(tester, const Key('expense-submit'));
      expect(_expenseLabel(tester), 'Menyimpan…');
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.updated, hasLength(2));
    });
  });

  // PR #25 independent pass: a second Simpan while a save runs is dropped,
  // and a failed save followed by a successful one pops exactly once.
  group('Double Simpan and error-then-success', () {
    /// Two taps in the same frame (the button has not rebuilt yet), then a
    /// third once it has.
    Future<void> tapThrice(WidgetTester tester, Key key) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.pump();
      await tester.tap(find.byKey(key), warnIfMissed: false);
      await tester.pump();
    }

    testWidgets('Setor: a double tap sends one deposit', (tester) async {
      final goals = _Goals()..gate = Completer<void>();
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      await tapThrice(tester, const Key('submit'));
      expect(goals.amounts, [20000]);
      expect(find.text('Menyimpan…'), findsOneWidget);

      goals.gate!.complete();
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(goals.amounts, [20000]);
    });

    testWidgets('Setor: a rejected deposit, then a retry that succeeds',
        (tester) async {
      final goals = _Goals(
        errors: [const ApiException('Nominal tidak valid'), null],
      )..gate = Completer<void>();
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      await _tap(tester, const Key('submit'));
      goals.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Nominal tidak valid'), findsOneWidget);
      expect(find.text('Menyimpan…'), findsNothing);
      expect(
        tester.widget<VillageButton>(find.byKey(const Key('submit'))).onPressed,
        isNotNull,
      );

      await _tap(tester, const Key('submit'));
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(goals.amounts, [20000, 20000]);
    });

    testWidgets('Setor: an unexpected error, then a retry that succeeds',
        (tester) async {
      final goals = _Goals(errors: [const FormatException('boom'), null])
        ..gate = Completer<void>();
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _tap(tester, const Key('submit')),
      );
      goals.gate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      _expectInlineUnexpected(
        tester,
        errorKey: const Key('submit-error'),
        submitKey: const Key('submit'),
      );

      // The retry clears the message and saves.
      await _tap(tester, const Key('submit'));
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(goals.amounts, [20000, 20000]);
    });

    testWidgets('Jajan: a double tap sends one expense', (tester) async {
      final expenses =
          FakeExpensesRepository(createResults: [fixtureExpenseCreated()])
            ..createGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.record,
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-25000'));
      await tapThrice(tester, const Key('expense-submit'));
      expect(expenses.created, hasLength(1));
      expect(_expenseLabel(tester), 'Menyimpan…');
      expect(_expenseEnabled(tester), isFalse);

      expenses.createGate!.complete();
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.created, hasLength(1));
    });

    testWidgets('Jajan: a failed save, then a retry that succeeds',
        (tester) async {
      final expenses = FakeExpensesRepository(
        createResults: [
          const ApiException('Gagal menyimpan'),
          fixtureExpenseCreated(),
        ],
      )..createGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.record,
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-25000'));
      await _tap(tester, const Key('expense-submit'));
      expenses.createGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Gagal menyimpan'), findsOneWidget);
      expect(_expenseLabel(tester), isNot('Menyimpan…'));
      expect(_expenseEnabled(tester), isTrue);

      await _tap(tester, const Key('expense-submit'));
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.created, hasLength(2));
    });

    testWidgets('Edit form: a double tap sends one update', (tester) async {
      final expenses = FakeExpensesRepository(
        updateResults: [_updatedWith(_row(amount: 15000))],
      )..updateGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.edit(499),
        extra: _row(),
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-15000'));
      await tapThrice(tester, const Key('expense-submit'));
      expect(expenses.updated, hasLength(1));
      expect(_expenseLabel(tester), 'Menyimpan…');

      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.updated, hasLength(1));
    });

    testWidgets('Edit form: a failed update, then a retry that succeeds',
        (tester) async {
      final expenses = FakeExpensesRepository(
        updateResults: [
          const NotFoundException(),
          _updatedWith(_row(amount: 15000)),
        ],
      )..updateGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.edit(499),
        extra: _row(),
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-15000'));
      await _tap(tester, const Key('expense-submit'));
      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Data tidak ditemukan.'), findsOneWidget);
      expect(_expenseEnabled(tester), isTrue);

      await _tap(tester, const Key('expense-submit'));
      await tester.pumpAndSettle();
      _expectOnMid(tester);
      expect(expenses.updated, hasLength(2));
      expect(expenses.updated.last.$2, {'amount': 15000});
    });
  });

  // PR #27 independent pass: the generic error only for unexpected
  // errors, and an erroring save whose screen is torn down (the stack is
  // replaced, which PopScope does not block) does not touch the dead state.
  group('PR #27 edge cases', () {
    testWidgets('Setor: a rejected deposit shows no generic error',
        (tester) async {
      final goals = _Goals(errors: [const ApiException('Nominal tidak valid')]);
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      await _tap(tester, const Key('submit'));
      await tester.pumpAndSettle();
      expect(find.text('Nominal tidak valid'), findsOneWidget);
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
    });

    testWidgets('Setor: a network failure shows no generic error',
        (tester) async {
      final goals = _Goals(errors: [const NetworkException()]);
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      await _tap(tester, const Key('submit'));
      await tester.pumpAndSettle();
      expect(find.byType(ContributeScreen), findsOneWidget);
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
    });

    testWidgets('Jajan: a rejected save shows no generic error',
        (tester) async {
      final expenses = FakeExpensesRepository(
        createResults: [const ApiException('Gagal menyimpan')],
      );
      await _pump(tester, location: ExpenseRoutes.record, expenses: expenses);

      await _tap(tester, const Key('expense-chip-25000'));
      await _tap(tester, const Key('expense-submit'));
      await tester.pumpAndSettle();
      expect(find.text('Gagal menyimpan'), findsOneWidget);
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
    });

    testWidgets('Edit form: a not-found update shows no generic error',
        (tester) async {
      final expenses = FakeExpensesRepository(
        updateResults: [const NotFoundException()],
      );
      await _pump(
        tester,
        location: ExpenseRoutes.edit(499),
        extra: _row(),
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-15000'));
      await _tap(tester, const Key('expense-submit'));
      await tester.pumpAndSettle();
      expect(find.text('Data tidak ditemukan.'), findsOneWidget);
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
    });

    /// Replaces the whole stack with '/', disposing the open form.
    Future<void> leave(WidgetTester tester, Type screen) async {
      GoRouter.of(tester.element(find.byType(screen))).go('/');
      await tester.pumpAndSettle();
      expect(find.byType(screen), findsNothing);
      expect(find.text('root'), findsOneWidget);
    }

    testWidgets('Setor: torn down during an erroring deposit', (tester) async {
      final goals = _Goals(errors: [const FormatException('boom')])
        ..gate = Completer<void>();
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);

      await _tap(tester, const Key('chip-20000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _tap(tester, const Key('submit')),
      );
      await leave(tester, ContributeScreen);

      goals.gate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      expect(tester.takeException(), isNull);
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
    });

    testWidgets('Jajan: torn down during an erroring save', (tester) async {
      final expenses = FakeExpensesRepository(
        createResults: [const FormatException('boom')],
      )..createGate = Completer<void>();
      await _pump(tester, location: ExpenseRoutes.record, expenses: expenses);

      await _tap(tester, const Key('expense-chip-25000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _tap(tester, const Key('expense-submit')),
      );
      await leave(tester, ContributeScreen);

      expenses.createGate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      expect(tester.takeException(), isNull);
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
    });

    testWidgets('Edit form: torn down during an erroring update',
        (tester) async {
      final expenses = FakeExpensesRepository(
        updateResults: [const FormatException('boom')],
      )..updateGate = Completer<void>();
      await _pump(
        tester,
        location: ExpenseRoutes.edit(499),
        extra: _row(),
        expenses: expenses,
      );

      await _tap(tester, const Key('expense-chip-15000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(
        errors,
        () => _tap(tester, const Key('expense-submit')),
      );
      await leave(tester, ExpenseEditScreen);

      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      expect(tester.takeException(), isNull);
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
    });

    testWidgets('Jajan: a double tap during an erroring save: one write',
        (tester) async {
      final expenses = FakeExpensesRepository(
        createResults: [const FormatException('boom')],
      )..createGate = Completer<void>();
      await _pump(tester, location: ExpenseRoutes.record, expenses: expenses);

      await _tap(tester, const Key('expense-chip-25000'));
      final errors = <Object>[];
      await collectUncaught<FormatException>(errors, () async {
        await tester.ensureVisible(_expenseSubmit);
        await tester.tap(_expenseSubmit);
        await tester.tap(_expenseSubmit);
        await tester.pump();
      });
      expect(expenses.created, hasLength(1));

      expenses.createGate!.complete();
      await tester.pumpAndSettle();
      expect(errors, [isA<FormatException>()]);
      expect(expenses.created, hasLength(1));
      expect(find.text(kUnexpectedErrorMessage), findsOneWidget);
      expect(_expenseEnabled(tester), isTrue);
    });
  });
}
