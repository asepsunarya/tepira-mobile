// Independent edge tests for Fase 8 T22: where the dock shows, what Catat
// opens, and the login round trip for the new routes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/app.dart';
import 'package:tepira_mobile/core/clock.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/data/expenses/expenses_repository.dart';
import 'package:tepira_mobile/data/expenses/last_expense_wallet_store.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/data/today/today_repository.dart';
import 'package:tepira_mobile/data/wallets/wallets_repository.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';
import 'package:tepira_mobile/features/auth/login_screen.dart';
import 'package:tepira_mobile/features/expenses/expense_edit_screen.dart';
import 'package:tepira_mobile/features/expenses/history_screen.dart';
import 'package:tepira_mobile/features/goals/contribute_screen.dart';
import 'package:tepira_mobile/features/goals/goals_screen.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';
import 'package:tepira_mobile/features/shell/app_dock.dart';
import 'package:tepira_mobile/features/wallets/wallets_screen.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_goals_repository.dart';
import '../../helpers/fake_last_expense_wallet_store.dart';
import '../../helpers/fake_today_repository.dart';
import '../../helpers/fake_wallets_repository.dart';

Future<ProviderContainer> _pumpApp(
  WidgetTester tester,
  AuthRepository repository,
) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      walletsRepositoryProvider
          .overrideWithValue(FakeWalletsRepository([fixtureWalletList()])),
      expensesRepositoryProvider.overrideWithValue(
        FakeExpensesRepository(listResults: [fixtureExpenseList()]),
      ),
      lastExpenseWalletStoreProvider
          .overrideWithValue(FakeLastExpenseWalletStore()),
      todayRepositoryProvider.overrideWithValue(FakeTodayRepository.budget()),
      goalsRepositoryProvider.overrideWithValue(
        FakeGoalsRepository(
          [
            [testGoal()],
          ],
          detailResults: [
            GoalDetail(goal: testGoal(id: 7), contributions: const []),
          ],
        ),
      ),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 1, 7)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const TepiraApp()),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
  return container;
}

Future<ProviderContainer> _signedIn(WidgetTester tester) =>
    _pumpApp(tester, FakeAuthRepository(restoredUser: testUser));

String _location(ProviderContainer container) => container
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .toString();

Future<void> _go(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  container.read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

DockTab? _selectedTab(WidgetTester tester) =>
    tester.widget<AppDock>(find.byType(AppDock)).current;

void main() {
  group('dock visibility', () {
    for (final (page, tab) in [
      ('/', DockTab.desa),
      (kHistoryPath, DockTab.riwayat),
      (WalletRoutes.list, DockTab.dompet),
    ]) {
      testWidgets('$page carries the dock with $tab selected', (tester) async {
        final container = await _signedIn(tester);

        await _go(tester, container, page);

        expect(find.byType(AppDock), findsOneWidget);
        expect(_selectedTab(tester), tab);
      });
    }

    for (final page in [
      ExpenseRoutes.record,
      GoalRoutes.recordFor(7),
      ExpenseRoutes.edit(499),
      WalletRoutes.edit(3),
    ]) {
      testWidgets('$page has no dock', (tester) async {
        final container = await _signedIn(tester);

        await _go(tester, container, page);

        expect(find.byType(AppDock), findsNothing);
      });
    }

    testWidgets('the login page has no dock', (tester) async {
      await _pumpApp(tester, FakeAuthRepository());

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AppDock), findsNothing);
    });

    testWidgets('/History/ (case and trailing slash) highlights Riwayat',
        (tester) async {
      final container = await _signedIn(tester);

      await _go(tester, container, '/History/');

      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(_selectedTab(tester), DockTab.riwayat);
    });

    testWidgets('tapping the selected tab does nothing', (tester) async {
      final container = await _signedIn(tester);
      await _tap(tester, 'dock-riwayat');

      await _tap(tester, 'dock-riwayat');

      expect(_location(container), kHistoryPath);
      expect(find.byType(HistoryScreen), findsOneWidget);
    });
  });

  group('Catat', () {
    for (final (page, screen) in [
      ('/', GoalsScreen),
      (kHistoryPath, HistoryScreen),
      (WalletRoutes.list, WalletsScreen),
    ]) {
      testWidgets('from $page opens Jajan on top and returns to $page',
          (tester) async {
        final container = await _signedIn(tester);
        await _go(tester, container, page);

        await _tap(tester, 'dock-catat');

        // Pushed over the page: the page stays below as the base location.
        expect(_location(container), page);
        expect(
          tester
              .widget<ContributeScreen>(find.byType(ContributeScreen))
              .tabParam,
          ExpenseRoutes.jajanTab,
        );
        expect(find.byType(AppDock), findsNothing);
        expect(container.read(routerProvider).canPop(), isTrue);

        container.read(routerProvider).pop();
        await tester.pumpAndSettle();
        expect(_location(container), page);
        expect(find.byType(screen), findsOneWidget);
        expect(find.byType(AppDock), findsOneWidget);
      });
    }
  });

  group('login redirect for the new routes', () {
    testWidgets(
        'signed out on /record?expense=499 signs in back to it; '
        'with no extra it shows the fallback', (tester) async {
      final container = await _pumpApp(tester, FakeAuthRepository());
      await _go(tester, container, ExpenseRoutes.edit(499));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        _location(container),
        '/login?from=${Uri.encodeComponent(ExpenseRoutes.edit(499))}',
      );

      await _tap(tester, 'google-sign-in');

      expect(_location(container), ExpenseRoutes.edit(499));
      expect(find.byType(ExpenseEditScreen), findsOneWidget);
      expect(find.byKey(const Key('expense-missing')), findsOneWidget);
    });

    testWidgets('signed out on /record?tab=jajan signs in back to Jajan',
        (tester) async {
      final container = await _pumpApp(tester, FakeAuthRepository());
      await _go(tester, container, ExpenseRoutes.record);

      expect(
        _location(container),
        '/login?from=${Uri.encodeComponent(ExpenseRoutes.record)}',
      );

      await _tap(tester, 'google-sign-in');

      expect(_location(container), ExpenseRoutes.record);
      expect(
        tester.widget<ContributeScreen>(find.byType(ContributeScreen)).tabParam,
        ExpenseRoutes.jajanTab,
      );
    });

    test('a ?from= pointing outside the app still lands on /', () {
      for (final from in ['//evil.example/history', 'https://x/history']) {
        final login = Uri(path: '/login', queryParameters: {'from': from});
        expect(authRedirect(const AuthSignedIn(testUser), login), '/');
      }
    });
  });
}
