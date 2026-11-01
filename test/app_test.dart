import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/app.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';
import 'package:tepira_mobile/features/auth/login_screen.dart';
import 'package:tepira_mobile/features/goals/goals_screen.dart';

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_session_store.dart';

void main() {
  group('authRedirect', () {
    test('unknown never redirects', () {
      expect(authRedirect(const AuthUnknown(), '/'), isNull);
      expect(authRedirect(const AuthUnknown(), '/login'), isNull);
    });

    test('signedOut goes to /login from anywhere else', () {
      expect(authRedirect(const AuthSignedOut(), '/'), '/login');
      expect(authRedirect(const AuthSignedOut(), '/goal/1'), '/login');
      expect(
        authRedirect(const AuthSignedOut(sessionExpired: true), '/'),
        '/login',
      );
      expect(authRedirect(const AuthSignedOut(), '/login'), isNull);
    });

    test('signedIn leaves /login for / and stays elsewhere', () {
      expect(authRedirect(const AuthSignedIn(testUser), '/login'), '/');
      expect(authRedirect(const AuthSignedIn(testUser), '/'), isNull);
      expect(authRedirect(const AuthSignedIn(testUser), '/goal/1'), isNull);
    });
  });

  group('TepiraApp routing', () {
    Future<ProviderContainer> pumpApp(
      WidgetTester tester,
      FakeAuthRepository repository, {
      bool settle = true,
    }) async {
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
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

    testWidgets('a stored session starts on /', (tester) async {
      await pumpApp(tester, FakeAuthRepository(restoredUser: testUser));

      expect(find.byType(GoalsScreen), findsOneWidget);
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
