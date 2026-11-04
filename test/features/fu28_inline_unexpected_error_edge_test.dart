// PR #28 independent pass: the generic unexpected save error
// (kUnexpectedErrorMessage) is shown inline in each form's red error line
// above Simpan instead of a snackbar.
//
// Clearing rules under test: every form clears it on the next submit;
// Setor and Jajan (create and edit) also clear it on an amount change (chip
// or keypad); the wallet and new goal forms keep it while fields are
// edited. The error itself is still rethrown to the zone handler.
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
import 'package:tepira_mobile/data/expenses/expense_dto.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/expenses/last_expense_wallet_store.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/expense_edit_screen.dart';
import 'package:tepira_mobile/features/expenses/model/expense.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';
import 'package:tepira_mobile/features/goals/contribute_screen.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';
import 'package:tepira_mobile/features/goals/model/new_goal_input.dart';
import 'package:tepira_mobile/features/goals/new_goal_screen.dart';
import 'package:tepira_mobile/features/wallets/model/wallet.dart';
import 'package:tepira_mobile/features/wallets/model/wallet_form_rules.dart';
import 'package:tepira_mobile/features/wallets/wallet_form_screen.dart';
import 'package:tepira_mobile/features/wallets/wallets_screen.dart';

import '../helpers/fake_expenses_repository.dart';
import '../helpers/fake_goals_repository.dart';
import '../helpers/fake_last_expense_wallet_store.dart';
import '../helpers/fake_today_repository.dart';
import '../helpers/fake_wallets_repository.dart';
import '../helpers/uncaught_errors.dart';

final _now = DateTime.utc(2026, 11, 1, 7);

/// Goals fake: [contribute] is gated and answers per call from [results]
/// (an [Object] other than null is thrown, so an [Error] can be thrown
/// too); [create] answers from [createResults] the same way.
class _Goals extends FakeGoalsRepository {
  _Goals({this.results = const [], this.createResults = const []})
      : super([
          [testGoal()],
        ]);

  final List<Object?> results;
  final List<Object?> createResults;
  final List<int> amounts = [];
  final List<String> titles = [];
  Completer<void>? gate;

  @override
  Future<void> contribute(int goalId, int amount, [String? note]) async {
    final call = amounts.length;
    amounts.add(amount);
    await gate?.future;
    final result = call < results.length ? results[call] : null;
    if (result != null) throw result;
  }

  @override
  Future<Goal> create({
    required String title,
    required int target,
    String? description,
    DateTime? deadline,
  }) async {
    final call = titles.length;
    titles.add(title);
    await gate?.future;
    final result = call < createResults.length ? createResults[call] : null;
    if (result != null) throw result;
    return testGoal(id: 16, title: title);
  }
}

Expense _row({int amount = 25000}) => testExpense(
      id: 499,
      amount: amount,
      category: 'Makan harian',
      note: 'nasi padang',
      date: DateTime.utc(2026, 11, 1, 5, 30),
    );

ExpenseUpdated _updatedWith(Expense expense) {
  final base = expenseUpdatedFromJson(readFixture('mobile_expense_updated'));
  return ExpenseUpdated(
    expense: expense,
    wallets: base.wallets,
    today: base.today,
  );
}

/// Pumps every form under test on top of a '/' -> '/mid' stack.
Future<GoRouter> _pump(
  WidgetTester tester, {
  required String location,
  Object? extra,
  _Goals? goals,
  FakeExpensesRepository? expenses,
  FakeWalletsRepository? wallets,
  Size size = const Size(390, 1400),
}) async {
  tester.view.physicalSize = size;
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
        path: GoalRoutes.create,
        builder: (context, state) => const NewGoalScreen(),
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
        walletsRepositoryProvider.overrideWithValue(
          wallets ?? FakeWalletsRepository([fixtureWalletList()]),
        ),
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
  return router;
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pump();
}

/// Taps [key] inside [collectUncaught], so the rethrown [T] is collected.
Future<void> _tapFailing<T extends Object>(
  WidgetTester tester,
  List<Object> errors,
  Key key,
) =>
    collectUncaught<T>(errors, () => _tap(tester, key));

/// Exactly one inline generic error, in the [errorKey] line, and no
/// snackbar, even after any snackbar entrance animation would have run.
Future<void> _expectInline(WidgetTester tester, Key errorKey) async {
  await tester.pump(const Duration(seconds: 1));
  expect(
    tester.widget<Text>(find.byKey(errorKey)).data,
    kUnexpectedErrorMessage,
  );
  expect(find.text(kUnexpectedErrorMessage), findsOneWidget);
  expect(find.byType(SnackBar), findsNothing);
}

void _expectNoGeneric(WidgetTester tester) {
  expect(find.text(kUnexpectedErrorMessage), findsNothing);
}

const _setorError = Key('submit-error');
const _setorSubmit = Key('submit');
const _jajanError = Key('expense-error');
const _jajanSubmit = Key('expense-submit');
const _formError = Key('submitError');

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<VillageButton>(find.byKey(key)).onPressed != null;

void main() {
  group('Setor', () {
    Future<_Goals> failOnce(WidgetTester tester, {Object? error}) async {
      final goals = _Goals(results: [error ?? const FormatException('boom')]);
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);
      await _tap(tester, const Key('chip-20000'));
      return goals;
    }

    testWidgets('a keypad press clears the inline error', (tester) async {
      await failOnce(tester);
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _setorError);

      await _tap(tester, const Key('key-5'));
      expect(find.byKey(_setorError), findsNothing);
      _expectNoGeneric(tester);
    });

    testWidgets('a keypad backspace also clears the inline error',
        (tester) async {
      await failOnce(tester);
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _setorError);

      await _tap(tester, const Key('key-${'⌫'}'));
      _expectNoGeneric(tester);
    });

    testWidgets('the error persists across note edits, scrolls and rebuilds',
        (tester) async {
      await failOnce(tester);
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _setorError);

      await tester.ensureVisible(find.byKey(const Key('note')));
      await tester.enterText(find.byKey(const Key('note')), 'sisa jajan');
      await tester.pump();
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -800));
      await tester.pumpAndSettle();
      // A forced rebuild of the whole tree (e.g. a MediaQuery change).
      tester.view.physicalSize = const Size(400, 1300);
      await tester.pumpAndSettle();
      await _expectInline(tester, _setorError);
    });

    testWidgets('a double tap during a failing deposit: one call, one error',
        (tester) async {
      final goals = _Goals(results: [const FormatException('boom')])
        ..gate = Completer<void>();
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);
      await _tap(tester, const Key('chip-20000'));

      final errors = <Object>[];
      await collectUncaught<FormatException>(errors, () async {
        await tester.ensureVisible(find.byKey(_setorSubmit));
        await tester.tap(find.byKey(_setorSubmit));
        await tester.tap(find.byKey(_setorSubmit));
        await tester.pump();
        await tester.tap(find.byKey(_setorSubmit), warnIfMissed: false);
        await tester.pump();
      });
      goals.gate!.complete();
      await tester.pumpAndSettle();

      expect(goals.amounts, [20000]);
      expect(errors, hasLength(1));
      await _expectInline(tester, _setorError);
    });

    testWidgets('the rethrown error is the very object thrown (an Error too)',
        (tester) async {
      final boom = StateError('bug');
      await failOnce(tester, error: boom);
      final errors = <Object>[];
      await _tapFailing<StateError>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();

      expect(errors, hasLength(1));
      expect(errors.single, same(boom));
      await _expectInline(tester, _setorError);
      expect(_enabled(tester, _setorSubmit), isTrue);
    });

    testWidgets('unexpected, then a rejected retry shows only the rejection',
        (tester) async {
      final goals = _Goals(
        results: [
          const FormatException('boom'),
          const ApiException('Nominal tidak valid'),
          null,
        ],
      );
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);
      await _tap(tester, const Key('chip-20000'));

      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _setorError);

      await _tap(tester, _setorSubmit);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(_setorError)).data,
        'Nominal tidak valid',
      );
      _expectNoGeneric(tester);

      await _tap(tester, _setorSubmit);
      await tester.pumpAndSettle();
      expect(find.text('mid'), findsOneWidget);
      expect(goals.amounts, [20000, 20000, 20000]);
      expect(errors, hasLength(1));
    });

    testWidgets('a network failure after an unexpected error clears it',
        (tester) async {
      final goals = _Goals(
        results: [const FormatException('boom'), const NetworkException()],
      );
      await _pump(tester, location: GoalRoutes.recordFor(1), goals: goals);
      await _tap(tester, const Key('chip-20000'));

      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _setorError);

      await _tap(tester, _setorSubmit);
      await tester.pumpAndSettle();
      expect(find.byKey(_setorError), findsNothing);
      _expectNoGeneric(tester);
    });
  });

  group('Jajan (create)', () {
    Future<FakeExpensesRepository> open(
      WidgetTester tester,
      List<Object> results,
    ) async {
      final expenses = FakeExpensesRepository(createResults: results);
      await _pump(tester, location: ExpenseRoutes.record, expenses: expenses);
      return expenses;
    }

    testWidgets('a keypad press clears the inline error', (tester) async {
      await open(tester, [const FormatException('boom')]);
      await _tap(tester, const Key('expense-chip-25000'));
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _jajanSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _jajanError);

      await _tap(tester, const Key('key-0'));
      expect(find.byKey(_jajanError), findsNothing);
      _expectNoGeneric(tester);
    });

    testWidgets('typing an amount clears the inline error', (tester) async {
      await open(tester, [const FormatException('boom')]);
      await _tap(tester, const Key('expense-chip-25000'));
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _jajanSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _jajanError);

      await tester.ensureVisible(find.byKey(const Key('expense-amount')));
      await tester.enterText(find.byKey(const Key('expense-amount')), '30000');
      await tester.pump();
      _expectNoGeneric(tester);
    });

    testWidgets('the error persists across category/note edits and scrolls',
        (tester) async {
      await open(tester, [const FormatException('boom')]);
      await _tap(tester, const Key('expense-chip-25000'));
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _jajanSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _jajanError);

      await _tap(tester, const Key('category-transport'));
      await tester.ensureVisible(find.byKey(const Key('expense-note')));
      await tester.enterText(find.byKey(const Key('expense-note')), 'soto');
      await tester.pump();
      await tester.drag(find.byType(ListView).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_jajanError));
      await _expectInline(tester, _jajanError);
    });

    testWidgets(
        'validation error, then unexpected, then a valid retry: '
        'each time only the right message', (tester) async {
      final expenses = await open(
        tester,
        [const FormatException('boom'), fixtureExpenseCreated()],
      );

      // Over the maximum: the form's own validation message.
      await tester.ensureVisible(find.byKey(const Key('expense-amount')));
      await tester.enterText(
        find.byKey(const Key('expense-amount')),
        '${kMaxExpenseAmount + 1}',
      );
      await tester.pump();
      await _tap(tester, _jajanSubmit);
      expect(
        tester.widget<Text>(find.byKey(_jajanError)).data,
        kExpenseAmountMessage,
      );
      expect(expenses.created, isEmpty);

      // A valid amount clears it; the save fails unexpectedly.
      await _tap(tester, const Key('expense-chip-25000'));
      expect(find.byKey(_jajanError), findsNothing);
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _jajanSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _jajanError);
      expect(find.text(kExpenseAmountMessage), findsNothing);

      // Over the maximum again: validation replaces the generic error.
      await tester.ensureVisible(find.byKey(const Key('expense-amount')));
      await tester.enterText(
        find.byKey(const Key('expense-amount')),
        '${kMaxExpenseAmount + 1}',
      );
      await tester.pump();
      await _tap(tester, _jajanSubmit);
      expect(
        tester.widget<Text>(find.byKey(_jajanError)).data,
        kExpenseAmountMessage,
      );
      _expectNoGeneric(tester);
      expect(expenses.created, hasLength(1));

      // A valid retry saves.
      await _tap(tester, const Key('expense-chip-25000'));
      await _tap(tester, _jajanSubmit);
      await tester.pumpAndSettle();
      expect(find.text('mid'), findsOneWidget);
      expect(expenses.created, hasLength(2));
      expect(errors, hasLength(1));
    });

    testWidgets('the success snackbar after a retry is the only snackbar',
        (tester) async {
      await open(
        tester,
        [const FormatException('boom'), fixtureExpenseCreated()],
      );
      await _tap(tester, const Key('expense-chip-25000'));
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _jajanSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _jajanError);

      await _tap(tester, _jajanSubmit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('tercatat'), findsOneWidget);
      _expectNoGeneric(tester);
    });
  });

  group('Jajan (edit)', () {
    Future<FakeExpensesRepository> open(
      WidgetTester tester,
      List<Object> results,
    ) async {
      final expenses = FakeExpensesRepository(updateResults: results);
      await _pump(
        tester,
        location: ExpenseRoutes.edit(499),
        extra: _row(),
        expenses: expenses,
      );
      await _tap(tester, const Key('expense-chip-15000'));
      return expenses;
    }

    testWidgets('a chip change clears the inline error; the retry saves',
        (tester) async {
      final expenses = await open(
        tester,
        [const FormatException('boom'), _updatedWith(_row(amount: 50000))],
      );
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _jajanSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _jajanError);

      await _tap(tester, const Key('expense-chip-50000'));
      expect(find.byKey(_jajanError), findsNothing);
      _expectNoGeneric(tester);
      expect(_enabled(tester, _jajanSubmit), isTrue);

      await _tap(tester, _jajanSubmit);
      await tester.pumpAndSettle();
      expect(find.text('mid'), findsOneWidget);
      expect(expenses.updated.last.$2, {'amount': 50000});
      expect(errors, hasLength(1));
    });

    testWidgets('a keypad press clears the inline error', (tester) async {
      await open(tester, [const FormatException('boom')]);
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _jajanSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _jajanError);

      await _tap(tester, const Key('key-${'⌫'}'));
      _expectNoGeneric(tester);
    });

    testWidgets('a double tap during a failing update: one call, one error',
        (tester) async {
      final expenses = await open(tester, [const FormatException('boom')]);
      expenses.updateGate = Completer<void>();
      final errors = <Object>[];
      await collectUncaught<FormatException>(errors, () async {
        await tester.ensureVisible(find.byKey(_jajanSubmit));
        await tester.tap(find.byKey(_jajanSubmit));
        await tester.tap(find.byKey(_jajanSubmit));
        await tester.pump();
      });
      expenses.updateGate!.complete();
      await tester.pumpAndSettle();
      expect(expenses.updated, hasLength(1));
      expect(errors, hasLength(1));
      await _expectInline(tester, _jajanError);
    });
  });

  group('Wallet form', () {
    final created = WalletWrite(wallet: testWallet(id: 22), totals: testTotals);

    Future<FakeWalletsRepository> open(
      WidgetTester tester,
      List<Object> results,
    ) async {
      final wallets = FakeWalletsRepository(
        [fixtureWalletList()],
        createResults: results,
      );
      await _pump(
        tester,
        location: WalletRoutes.create,
        wallets: wallets,
        size: const Size(390, 1800),
      );
      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      return wallets;
    }

    testWidgets('field edits keep the error; a validation submit clears it',
        (tester) async {
      final wallets = await open(tester, [const FormatException('boom')]);
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _formError);

      // Editing the fields does not clear it.
      await tester.enterText(find.byKey(const Key('name')), 'Dompet baru');
      await tester.pump();
      await tester.tap(find.byKey(const Key('type-bank')));
      await tester.pump();
      await _expectInline(tester, _formError);

      // A submit that fails validation clears it: only the field error.
      await tester.enterText(find.byKey(const Key('name')), '');
      await _tap(tester, _setorSubmit);
      await tester.pumpAndSettle();
      expect(find.text(kWalletNameError), findsOneWidget);
      expect(find.byKey(_formError), findsNothing);
      _expectNoGeneric(tester);
      expect(wallets.created, hasLength(1));
    });

    testWidgets(
        'validation error, then unexpected, then a valid retry that saves',
        (tester) async {
      final wallets = await open(
        tester,
        [const FormatException('boom'), created],
      );
      await tester.enterText(find.byKey(const Key('name')), '');
      await _tap(tester, _setorSubmit);
      await tester.pumpAndSettle();
      expect(find.text(kWalletNameError), findsOneWidget);

      await tester.enterText(find.byKey(const Key('name')), 'Dompet');
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _formError);
      expect(find.text(kWalletNameError), findsNothing);

      await _tap(tester, _setorSubmit);
      await tester.pumpAndSettle();
      expect(find.byType(WalletFormScreen), findsNothing);
      expect(wallets.created, hasLength(2));
      expect(errors, hasLength(1));
    });

    testWidgets('a double tap during a failing save: one call, one error',
        (tester) async {
      final wallets = await open(tester, [const FormatException('boom')]);
      wallets.writeGate = Completer<void>();
      final errors = <Object>[];
      await collectUncaught<FormatException>(errors, () async {
        await tester.tap(find.byKey(_setorSubmit));
        await tester.tap(find.byKey(_setorSubmit));
        await tester.pump();
      });
      wallets.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(wallets.created, hasLength(1));
      expect(errors, hasLength(1));
      await _expectInline(tester, _formError);
    });

    testWidgets('edit: an unexpected update error is inline and retryable',
        (tester) async {
      final list = fixtureWalletList();
      final wallet = list.wallets.first;
      final wallets = FakeWalletsRepository(
        [list],
        updateResults: [
          const FormatException('boom'),
          WalletWrite(wallet: wallet, totals: list.totals),
        ],
      );
      await _pump(
        tester,
        location: WalletRoutes.list,
        wallets: wallets,
        size: const Size(390, 1800),
      );
      GoRouter.of(tester.element(find.byType(WalletsScreen)))
          .push(WalletRoutes.edit(wallet.id));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('name')), 'Rekening');
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      await _expectInline(tester, _formError);
      expect(find.byType(WalletFormScreen), findsOneWidget);

      await _tap(tester, _setorSubmit);
      expect(find.text(kUnexpectedErrorMessage), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(WalletFormScreen), findsNothing);
      expect(wallets.updated, hasLength(2));
      expect(errors, hasLength(1));
    });
  });

  group('New goal', () {
    Future<_Goals> open(WidgetTester tester, List<Object?> results) async {
      final goals = _Goals(createResults: results);
      await _pump(
        tester,
        location: GoalRoutes.create,
        goals: goals,
        size: const Size(390, 844),
      );
      await tester.enterText(find.byKey(const Key('title')), 'Kamera');
      await tester.enterText(find.byKey(const Key('target')), '9000000');
      return goals;
    }

    testWidgets('field edits and scrolling keep the error', (tester) async {
      await open(tester, [const FormatException('boom')]);
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_formError));
      await _expectInline(tester, _formError);

      await tester.enterText(find.byKey(const Key('title')), 'Kamera baru');
      await tester.enterText(find.byKey(const Key('target')), '8000000');
      await tester.pump();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 500));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_formError));
      await tester.pumpAndSettle();
      await _expectInline(tester, _formError);
    });

    testWidgets(
        'validation error, then unexpected, then a valid retry that saves',
        (tester) async {
      final goals = await open(tester, [const FormatException('boom')]);
      await tester.enterText(find.byKey(const Key('title')), '');
      await _tap(tester, _setorSubmit);
      await tester.pumpAndSettle();
      expect(find.text(NewGoalInput.titleError('')!), findsOneWidget);
      expect(goals.titles, isEmpty);

      await tester.enterText(find.byKey(const Key('title')), 'Kamera');
      final errors = <Object>[];
      await _tapFailing<FormatException>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_formError));
      await _expectInline(tester, _formError);
      expect(find.text(NewGoalInput.titleError('')!), findsNothing);

      // A submit that fails validation clears the generic error.
      await tester.enterText(find.byKey(const Key('target')), '');
      await _tap(tester, _setorSubmit);
      await tester.pumpAndSettle();
      expect(find.text(NewGoalInput.targetError('')!), findsOneWidget);
      _expectNoGeneric(tester);

      await tester.enterText(find.byKey(const Key('target')), '9000000');
      await _tap(tester, _setorSubmit);
      await tester.pumpAndSettle();
      expect(find.text('goal /goal/16'), findsOneWidget);
      expect(goals.titles, ['Kamera', 'Kamera']);
      expect(errors, hasLength(1));
    });

    testWidgets('the rethrown error is the very object thrown (an Error too)',
        (tester) async {
      final boom = StateError('bug');
      await open(tester, [boom]);
      final errors = <Object>[];
      await _tapFailing<StateError>(tester, errors, _setorSubmit);
      await tester.pumpAndSettle();
      expect(errors.single, same(boom));
      await tester.ensureVisible(find.byKey(_formError));
      await _expectInline(tester, _formError);
    });
  });
}
