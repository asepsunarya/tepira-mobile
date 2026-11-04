// Independent edge tests for pasted amounts (fix round on PR #22): digits
// too many to parse count as over the limit, with or without separators.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/clock.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/expenses/last_expense_wallet_store.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/expenses/model/expense_input.dart';
import 'package:tepira_mobile/features/goals/contribute_screen.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_goals_repository.dart';
import '../../helpers/fake_last_expense_wallet_store.dart';
import '../../helpers/fake_wallets_repository.dart';

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

Finder get _amount => find.byKey(const Key('expense-amount'));
Finder get _submit => find.byKey(const Key('expense-submit'));

String _submitLabel(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _submit, matching: find.byType(Text)))
    .data!;

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_amount).controller!.text;

Future<void> _paste(WidgetTester tester, String text) async {
  await tester.enterText(_amount, text);
  await tester.pump();
}

/// Taps Simpan and expects the over-limit message, nothing sent.
Future<void> _expectRefused(WidgetTester tester, _Harness h) async {
  expect(_submitLabel(tester), 'Simpan');
  await tester.tap(_submit);
  await tester.pumpAndSettle();
  expect(find.text(kExpenseAmountMessage), findsOneWidget);
  expect(h.expenses.created, isEmpty);
}

void main() {
  group('huge pasted amounts', () {
    for (final pasted in [
      '1.000.000.000.000.000.000.000',
      'Rp1.000.000.000.000.000.000.000',
      'Rp 99.999.999.999.999.999.999,50',
      '9.223.372.036.854.775.808',
      '1 000 000 000 000 000 000 000',
      '12345678901234567890123456789012345678901234567890',
    ]) {
      testWidgets('"$pasted" is over the limit, never 0 or a wrapped value',
          (tester) async {
        final h = _Harness();
        await h.open(tester);

        await _paste(tester, pasted);

        expect(_fieldText(tester), isNot(isEmpty));
        expect(_fieldText(tester), isNot('0'));
        await _expectRefused(tester, h);
      });
    }

    testWidgets('the largest int (9.223.372.036.854.775.807) is over the limit',
        (tester) async {
      final h = _Harness();
      await h.open(tester);

      await _paste(tester, '9.223.372.036.854.775.807');

      await _expectRefused(tester, h);
    });

    testWidgets('100.000.001 is refused, 100.000.000 is sent', (tester) async {
      final h = _Harness();
      await h.open(tester);

      await _paste(tester, '100.000.001');
      await _expectRefused(tester, h);

      await _paste(tester, '100.000.000');
      expect(_submitLabel(tester), 'Simpan Rp100.000.000');
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(h.expenses.created.single.amount, 100000000);
    });

    testWidgets('a long run of leading zeros is a normal amount',
        (tester) async {
      final h = _Harness();
      await h.open(tester);

      await _paste(tester, '000.000.000.000.000.000.000.000.025.000');

      expect(_fieldText(tester), '25.000');
      expect(_submitLabel(tester), 'Simpan Rp25.000');
    });

    testWidgets('after a huge paste, a chip brings back a valid amount',
        (tester) async {
      final h = _Harness();
      await h.open(tester);

      await _paste(tester, '1.000.000.000.000.000.000.000');
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(find.text(kExpenseAmountMessage), findsOneWidget);

      await tester.tap(find.byKey(const Key('expense-chip-25000')));
      await tester.pumpAndSettle();
      expect(_submitLabel(tester), 'Simpan Rp25.000');
      expect(find.text(kExpenseAmountMessage), findsNothing);
      await tester.tap(_submit);
      await tester.pumpAndSettle();
      expect(h.expenses.created.single.amount, 25000);
    });
  });
}
