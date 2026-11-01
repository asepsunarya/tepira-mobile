import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/app.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';
import 'package:tepira_mobile/features/auth/login_screen.dart';
import 'package:tepira_mobile/features/goals/goals_screen.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_goals_repository.dart';
import 'helpers/fake_session_store.dart';

void main() {
  group('authRedirect', () {
    String? redirect(AuthState auth, String location) =>
        authRedirect(auth, Uri.parse(location));

    test('unknown never redirects', () {
      expect(redirect(const AuthUnknown(), '/'), isNull);
      expect(redirect(const AuthUnknown(), '/login'), isNull);
      expect(redirect(const AuthUnknown(), '/goal/1'), isNull);
    });

    test('signedOut goes to /login from /', () {
      expect(redirect(const AuthSignedOut(), '/'), '/login');
      expect(
        redirect(const AuthSignedOut(sessionExpired: true), '/'),
        '/login',
      );
      expect(redirect(const AuthSignedOut(), '/login'), isNull);
      expect(
        redirect(const AuthSignedOut(), '/login?from=%2Fgoal%2F1'),
        isNull,
      );
    });

    test('signedOut remembers any other page in ?from', () {
      expect(
        redirect(const AuthSignedOut(), '/goal/1'),
        '/login?from=%2Fgoal%2F1',
      );
      expect(
        redirect(const AuthSignedOut(sessionExpired: true), '/record?goal=3'),
        '/login?from=%2Frecord%3Fgoal%3D3',
      );
    });

    test('signedIn leaves /login for / and stays elsewhere', () {
      expect(redirect(const AuthSignedIn(testUser), '/login'), '/');
      expect(redirect(const AuthSignedIn(testUser), '/'), isNull);
      expect(redirect(const AuthSignedIn(testUser), '/goal/1'), isNull);
    });

    test('signedIn on /login returns to the remembered page', () {
      expect(
        redirect(const AuthSignedIn(testUser), '/login?from=%2Fgoal%2F1'),
        '/goal/1',
      );
      expect(
        redirect(
          const AuthSignedIn(testUser),
          '/login?from=%2Frecord%3Fgoal%3D3',
        ),
        '/record?goal=3',
      );
    });

    test('signedIn ignores a remembered page outside the app', () {
      for (final from in [
        'https://evil.example/x',
        '//evil.example/x',
        'goal/1',
        '/login',
        '/login?from=%2Fgoal%2F1',
        '',
      ]) {
        final login = Uri(path: '/login', queryParameters: {'from': from});
        expect(
          authRedirect(const AuthSignedIn(testUser), login),
          '/',
          reason: from,
        );
      }
    });
  });

  group('TepiraApp routing', () {
    Future<ProviderContainer> pumpApp(
      WidgetTester tester,
      FakeAuthRepository repository, {
      bool settle = true,
    }) async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          goalsRepositoryProvider.overrideWithValue(
            FakeGoalsRepository([
              [testGoal()],
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TepiraApp(),
        ),
      );
      await tester.runAsync(GoogleFonts.pendingFonts);
      // The restoring loader spins forever, so it never settles.
      settle ? await tester.pumpAndSettle() : await tester.pump();
      return container;
    }

    testWidgets('shows a loader while the session is restored', (tester) async {
      final repository = FakeAuthRepository()..restoreGate = Completer<void>();
      await pumpApp(tester, repository, settle: false);

      expect(find.bySemanticsLabel('Memuat sesi'), findsOneWidget);
      expect(find.byType(GoalsScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);

      repository.restoreGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('signed out starts on /login', (tester) async {
      await pumpApp(tester, FakeAuthRepository());

      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('a stored session starts on / with the user name',
        (tester) async {
      await pumpApp(tester, FakeAuthRepository(restoredUser: testUser));

      expect(find.byType(GoalsScreen), findsOneWidget);
      expect(find.text('Asep'), findsOneWidget);
      expect(find.text('Dana darurat'), findsOneWidget);
    });

    for (final (path, title) in [
      ('/goal/new', 'Bangun kavling'),
      ('/goal/7', 'Kavling'),
      ('/record', 'Catat'),
    ]) {
      testWidgets('$path has a placeholder page until its task lands',
          (tester) async {
        final container =
            await pumpApp(tester, FakeAuthRepository(restoredUser: testUser));

        container.read(routerProvider).go(path);
        await tester.pumpAndSettle();

        expect(find.text(title), findsOneWidget);
        expect(find.text('Segera hadir'), findsOneWidget);
      });
    }

    testWidgets('signing in returns to the page asked for while signed out',
        (tester) async {
      final container = await pumpApp(tester, FakeAuthRepository());
      container.read(routerProvider).go('/goal/7');
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('google-sign-in')));
      await tester.pumpAndSettle();

      expect(find.text('Kavling'), findsOneWidget);
      final router = container.read(routerProvider);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/goal/7');
    });

    testWidgets('signing in moves /login to /', (tester) async {
      await pumpApp(tester, FakeAuthRepository());

      await tester.tap(find.byKey(const Key('google-sign-in')));
      await tester.pumpAndSettle();

      expect(find.byType(GoalsScreen), findsOneWidget);
    });

    testWidgets('a 401 anywhere returns to /login with the overlay',
        (tester) async {
      final store = FakeSessionStore(token: 'jwe', userJson: '{}');
      final container = await pumpApp(
        tester,
        FakeAuthRepository(restoredUser: testUser, store: store),
      );

      container.read(unauthorizedEventsProvider).notify();
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sesi desamu sudah berakhir'), findsOneWidget);
      expect(store.token, isNull);
    });

    testWidgets('signing out clears the store and returns to /login',
        (tester) async {
      final store = FakeSessionStore(token: 'jwe', userJson: '{}');
      final container = await pumpApp(
        tester,
        FakeAuthRepository(restoredUser: testUser, store: store),
      );

      await container.read(authStateProvider.notifier).signOut();
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sesi desamu sudah berakhir'), findsNothing);
      expect(store.token, isNull);
    });
  });
}
