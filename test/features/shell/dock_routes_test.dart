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
import 'package:tepira_mobile/features/goals/goal_detail_screen.dart';
import 'package:tepira_mobile/features/goals/goals_screen.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';
import 'package:tepira_mobile/features/goals/new_goal_screen.dart';
import 'package:tepira_mobile/features/shell/app_dock.dart';
import 'package:tepira_mobile/features/wallets/wallet_form_screen.dart';
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
  group('authRedirect for the dock pages', () {
    test('signed out remembers /history and /wallets in ?from', () {
      expect(
        authRedirect(const AuthSignedOut(), Uri.parse(kHistoryPath)),
        '/login?from=%2Fhistory',
      );
      expect(
        authRedirect(const AuthSignedOut(), Uri.parse(WalletRoutes.list)),
        '/login?from=%2Fwallets',
      );
      expect(
        authRedirect(
          const AuthSignedOut(),
          Uri.parse(ExpenseRoutes.edit(499)),
        ),
        '/login?from=%2Frecord%3Fexpense%3D499',
      );
    });

    test('signing in returns to /history and /wallets', () {
      for (final page in [kHistoryPath, WalletRoutes.list]) {
        final login = Uri(path: '/login', queryParameters: {'from': page});
        expect(authRedirect(const AuthSignedIn(testUser), login), page);
      }
    });

    test('signed in stays on the dock pages', () {
      for (final page in [kHistoryPath, WalletRoutes.list]) {
        expect(
          authRedirect(const AuthSignedIn(testUser), Uri.parse(page)),
          isNull,
        );
      }
    });
  });

  group('dock', () {
    testWidgets('Desa shows the dock with Desa selected', (tester) async {
      await _signedIn(tester);

      expect(find.byType(GoalsScreen), findsOneWidget);
      expect(find.byType(AppDock), findsOneWidget);
      expect(_selectedTab(tester), DockTab.desa);
      for (final label in ['Desa', 'Riwayat', 'Catat', 'Dompet']) {
        expect(
          find.descendant(of: find.byType(AppDock), matching: find.text(label)),
          findsOneWidget,
        );
      }
    });

    testWidgets('the tabs are in the order Desa, Riwayat, Catat, Dompet',
        (tester) async {
      await _signedIn(tester);

      final xs = [
        for (final tab in ['desa', 'riwayat', 'catat', 'dompet'])
          tester.getCenter(find.byKey(Key('dock-$tab'))).dx,
      ];
      expect(xs, [...xs]..sort());
    });

    testWidgets('Riwayat and Dompet switch pages and keep the dock',
        (tester) async {
      final container = await _signedIn(tester);

      await _tap(tester, 'dock-riwayat');
      expect(_location(container), kHistoryPath);
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(_selectedTab(tester), DockTab.riwayat);

      await _tap(tester, 'dock-dompet');
      expect(_location(container), WalletRoutes.list);
      expect(find.byType(WalletsScreen), findsOneWidget);
      expect(_selectedTab(tester), DockTab.dompet);

      await _tap(tester, 'dock-desa');
      expect(_location(container), '/');
      expect(find.byType(GoalsScreen), findsOneWidget);
      expect(_selectedTab(tester), DockTab.desa);
    });

    testWidgets('Catat opens the Jajan tab on top; closing returns',
        (tester) async {
      final container = await _signedIn(tester);
      await _tap(tester, 'dock-riwayat');

      await _tap(tester, 'dock-catat');

      final screen =
          tester.widget<ContributeScreen>(find.byType(ContributeScreen));
      expect(screen.tabParam, ExpenseRoutes.jajanTab);
      expect(find.byType(AppDock), findsNothing);

      container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(_location(container), kHistoryPath);
      expect(find.byType(HistoryScreen), findsOneWidget);
    });

    testWidgets('a page outside the dock has no dock', (tester) async {
      final container = await _signedIn(tester);

      for (final page in [
        GoalRoutes.create,
        GoalRoutes.detail(7),
        WalletRoutes.create,
        kSettingsPath,
      ]) {
        await _go(tester, container, page);
        expect(find.byType(AppDock), findsNothing, reason: page);
      }
    });

    test('forPath ignores case and one trailing slash, like go_router', () {
      expect(DockTab.forPath('/'), DockTab.desa);
      expect(DockTab.forPath('/history'), DockTab.riwayat);
      expect(DockTab.forPath('/History/'), DockTab.riwayat);
      expect(DockTab.forPath('/wallets'), DockTab.dompet);
      expect(DockTab.forPath('/wallets/new'), isNull);
      expect(DockTab.forPath('/record'), isNull);
    });
  });

  group('deep links', () {
    testWidgets('/history opens Riwayat', (tester) async {
      final container = await _signedIn(tester);

      await _go(tester, container, kHistoryPath);

      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('expense-499')), findsOneWidget);
    });

    testWidgets('/wallets opens Dompet', (tester) async {
      final container = await _signedIn(tester);

      await _go(tester, container, WalletRoutes.list);

      expect(find.byType(WalletsScreen), findsOneWidget);
      expect(_selectedTab(tester), DockTab.dompet);
    });

    testWidgets('the v1 and v2 links still open their screens', (tester) async {
      final container = await _signedIn(tester);

      await _go(tester, container, GoalRoutes.recordFor(7));
      expect(
        tester
            .widget<ContributeScreen>(find.byType(ContributeScreen))
            .goalParam,
        '7',
      );
      await _go(tester, container, GoalRoutes.detail(7));
      expect(find.byType(GoalDetailScreen), findsOneWidget);
      await _go(tester, container, GoalRoutes.create);
      expect(find.byType(NewGoalScreen), findsOneWidget);
      await _go(tester, container, WalletRoutes.create);
      expect(find.byType(WalletFormScreen), findsOneWidget);
      await _go(tester, container, WalletRoutes.edit(3));
      expect(find.byType(WalletFormScreen), findsOneWidget);
    });

    testWidgets('/record?expense= without the listed row opens the hint',
        (tester) async {
      final container = await _signedIn(tester);

      await _go(tester, container, ExpenseRoutes.edit(499));

      expect(find.byType(ExpenseEditScreen), findsOneWidget);
      expect(find.byKey(const Key('expense-missing')), findsOneWidget);

      await _tap(tester, 'open-history');
      expect(_location(container), kHistoryPath);
    });

    testWidgets('/record?expense= with a bad id opens the hint, not Setor',
        (tester) async {
      final container = await _signedIn(tester);

      await _go(tester, container, '/record?expense=0x1F');

      expect(find.byKey(const Key('expense-missing')), findsOneWidget);
      expect(find.byType(ContributeScreen), findsNothing);
    });

    testWidgets('Riwayat Ubah opens the filled form through the router',
        (tester) async {
      await _signedIn(tester);
      await _tap(tester, 'dock-riwayat');

      await _tap(tester, 'expense-499');
      await _tap(tester, 'expense-edit');

      expect(find.byType(ExpenseEditScreen), findsOneWidget);
      expect(find.byKey(const Key('expense-missing')), findsNothing);
      expect(find.byKey(const Key('expense-submit')), findsOneWidget);
    });

    for (final page in [kHistoryPath, WalletRoutes.list]) {
      testWidgets('signed out on $page signs in back to $page', (tester) async {
        final container = await _pumpApp(tester, FakeAuthRepository());
        await _go(tester, container, page);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(
          _location(container),
          '/login?from=${Uri.encodeComponent(page)}',
        );

        await _tap(tester, 'google-sign-in');

        expect(_location(container), page);
        expect(find.byType(AppDock), findsOneWidget);
      });
    }
  });
}
