import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/app.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';
import 'package:tepira_mobile/features/auth/login_screen.dart';
import 'package:tepira_mobile/features/goals/goals_screen.dart';
import 'package:tepira_mobile/features/settings/settings_screen.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_goals_repository.dart';
import '../../helpers/fake_google_id_token_source.dart';
import '../../helpers/fake_session_store.dart';

/// [FakeAuthRepository] whose sign-out can fail before touching the store.
class _FlakyAuthRepository extends FakeAuthRepository {
  _FlakyAuthRepository({super.restoredUser, super.store});

  Object? signOutError;

  @override
  Future<void> signOut() async {
    final error = signOutError;
    if (error != null) {
      signOutCalls++;
      throw error;
    }
    await super.signOut();
  }
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester,
  AuthRepository repository,
) async {
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
  await tester.pumpAndSettle();
  return container;
}

GoRouter _router(ProviderContainer container) => container.read(routerProvider);

String _location(ProviderContainer container) =>
    _router(container).routerDelegate.currentConfiguration.uri.toString();

/// Path of the page on top, including pages opened with `push` (which
/// go_router 14 leaves out of `currentConfiguration.uri`).
String _top(ProviderContainer container) =>
    _router(container).routerDelegate.currentConfiguration.last.matchedLocation;

/// Number of pages in go_router's stack.
int _depth(ProviderContainer container) =>
    _router(container).routerDelegate.currentConfiguration.matches.length;

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pumpAndSettle();
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('sign-out')));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await _openDialog(tester);
  await tester.tap(find.byKey(const Key('confirm-sign-out')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('double-tapping the HUD avatar opens Pengaturan once',
      (tester) async {
    final container =
        await _pumpApp(tester, FakeAuthRepository(restoredUser: testUser));

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(
      find.byKey(const Key('open-settings')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(_top(container), kSettingsPath);
    expect(_depth(container), 2, reason: '/ then /settings, not twice');
    expect(
      find.byType(SettingsScreen, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('double-tapping confirm signs out once and ends on /login',
      (tester) async {
    final store = FakeSessionStore(token: 'jwe', userJson: '{}');
    final repository = FakeAuthRepository(restoredUser: testUser, store: store)
      ..signOutGate = Completer<void>();
    final container = await _pumpApp(tester, repository);
    await _openSettings(tester);
    await _openDialog(tester);

    final confirm = find.byKey(const Key('confirm-sign-out'));
    await tester.tap(confirm);
    await tester.pump();
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm, warnIfMissed: false);
    }
    await tester.pumpAndSettle();
    // Still on Pengaturan while the sign-out runs: the second tap did not
    // pop /settings.
    expect(find.byType(SettingsScreen), findsOneWidget);

    repository.signOutGate!.complete();
    await tester.pumpAndSettle();

    expect(repository.signOutCalls, 1);
    expect(_location(container), '/login');
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('back during a slow sign-out still ends on a plain /login',
      (tester) async {
    final store = FakeSessionStore(token: 'jwe', userJson: '{}');
    final repository = FakeAuthRepository(restoredUser: testUser, store: store)
      ..signOutGate = Completer<void>();
    final container = await _pumpApp(tester, repository);
    await _openSettings(tester);
    await _confirm(tester);

    // Android back while the store is being cleared.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(GoalsScreen), findsOneWidget);

    repository.signOutGate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.signOutCalls, 1);
    expect(store.token, isNull);
    expect(store.userJson, isNull);
    expect(_location(container), '/login');
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('after sign-out the back stack holds only /login',
      (tester) async {
    final container =
        await _pumpApp(tester, FakeAuthRepository(restoredUser: testUser));
    await _openSettings(tester);
    await _confirm(tester);

    expect(_location(container), '/login');
    expect(_depth(container), 1);
    expect(_router(container).canPop(), isFalse);

    // System back must not reveal Pengaturan or the Desa.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(GoalsScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);

    // Nor does going there directly.
    for (final path in [kSettingsPath, kHomePath]) {
      _router(container).go(path);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget, reason: path);
      expect(find.byType(SettingsScreen), findsNothing, reason: path);
      expect(find.byType(GoalsScreen), findsNothing, reason: path);
    }
  });

  testWidgets('signed out, /settings redirects to /login and remembers it',
      (tester) async {
    final container = await _pumpApp(tester, FakeAuthRepository());

    _router(container).go(kSettingsPath);
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(_location(container), '/login?from=%2Fsettings');
  });

  testWidgets(
      'the store is empty after sign-out and a restart stays signed '
      'out', (tester) async {
    final store = FakeSessionStore(
      token: 'jwe',
      userJson: jsonEncode(testUser.toJson()),
    );
    final google = FakeGoogleIdTokenSource();
    await _pumpApp(
      tester,
      ApiAuthRepository(dio: Dio(), sessionStore: store, google: google),
    );
    expect(find.byType(GoalsScreen), findsOneWidget);
    await _openSettings(tester);
    await _confirm(tester);

    expect(store.token, isNull);
    expect(store.userJson, isNull);
    expect(google.signOutCalls, 1);

    // Cold start with the same store.
    await tester.pumpWidget(const SizedBox());
    final restarted = await _pumpApp(
      tester,
      ApiAuthRepository(dio: Dio(), sessionStore: store, google: google),
    );
    expect(restarted.read(authStateProvider), const AuthSignedOut());
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets(
      'signing in again after Keluar lands on the Desa, not '
      'Pengaturan', (tester) async {
    final repository = FakeAuthRepository(restoredUser: testUser);
    final container = await _pumpApp(tester, repository);
    await _openSettings(tester);
    await _confirm(tester);
    expect(_location(container), '/login');

    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pumpAndSettle();

    expect(find.byType(GoalsScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(_location(container), '/');
    expect(_depth(container), 1);
  });

  testWidgets(
      'Keluar from a deep-linked /settings lands on a plain /login, '
      'and signing in opens the Desa', (tester) async {
    final repository = FakeAuthRepository(restoredUser: testUser);
    final container = await _pumpApp(tester, repository);
    // `go`, not `push`: /settings is the base location, as after a deep link
    // or a remembered ?from=/settings.
    _router(container).go(kSettingsPath);
    await tester.pumpAndSettle();
    expect(_location(container), kSettingsPath);

    await _confirm(tester);
    expect(_location(container), '/login');

    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pumpAndSettle();
    expect(_location(container), '/');
    expect(find.byType(GoalsScreen), findsOneWidget);
  });

  testWidgets('a failed sign-out keeps the session, the store and the page',
      (tester) async {
    final store = FakeSessionStore(token: 'jwe', userJson: '{}');
    final repository =
        _FlakyAuthRepository(restoredUser: testUser, store: store)
          ..signOutError = Exception('keystore locked');
    final container = await _pumpApp(tester, repository);
    await _openSettings(tester);

    await _confirm(tester);

    expect(find.text(kSignOutFailedMessage), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(_top(container), kSettingsPath);
    expect(container.read(authStateProvider), const AuthSignedIn(testUser));
    expect(store.token, 'jwe');

    // Retry succeeds.
    repository.signOutError = null;
    await _confirm(tester);
    expect(_location(container), '/login');
    expect(store.token, isNull);
    expect(repository.signOutCalls, 2);
  });

  testWidgets(
      'a 401 during a slow sign-out still ends on /login without the '
      'overlay', (tester) async {
    final repository = FakeAuthRepository(restoredUser: testUser)
      ..signOutGate = Completer<void>();
    final container = await _pumpApp(tester, repository);
    await _openSettings(tester);
    await _confirm(tester);

    container.read(unauthorizedEventsProvider).notify();
    await tester.pumpAndSettle();
    repository.signOutGate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(_location(container), '/login');
  });
}
