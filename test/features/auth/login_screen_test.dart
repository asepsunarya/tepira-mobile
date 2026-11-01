import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/api_client.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/data/auth/google_id_token_source.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';
import 'package:tepira_mobile/features/auth/login_screen.dart';

import '../../helpers/fake_auth_repository.dart';

Future<ProviderContainer> _pumpLogin(
  WidgetTester tester,
  FakeAuthRepository repository,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildVillageTheme(), home: const LoginScreen()),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tapGoogle(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('google-sign-in')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the Login artboard copy', (tester) async {
    await _pumpLogin(tester, FakeAuthRepository());

    expect(find.text('Masuk dengan Google'), findsOneWidget);
    expect(find.text('desa tabunganmu'), findsOneWidget);
    expect(find.text('Dana darurat · tahap dinding'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the button signs in', (tester) async {
    final repository = FakeAuthRepository();
    final container = await _pumpLogin(tester, repository);

    await _tapGoogle(tester);

    expect(repository.signInCalls, 1);
    expect(container.read(authStateProvider), const AuthSignedIn(testUser));
  });

  final errors = <String, (AppException, String)>{
    '403 not_allowed': (
      const ForbiddenException(
        message: kNotAllowedMessage,
        code: 'not_allowed',
      ),
      'Akun ini belum terdaftar di tepira.id',
    ),
    '401 invalid_token': (
      const ApiException(kInvalidTokenMessage, statusCode: 401),
      kInvalidTokenMessage,
    ),
    '429': (
      const ApiException(kTooManyAttemptsMessage, statusCode: 429),
      kTooManyAttemptsMessage,
    ),
    'network': (const NetworkException(), 'Koneksi bermasalah. Coba lagi.'),
  };
  for (final MapEntry(key: name, value: (error, message)) in errors.entries) {
    testWidgets('$name shows "$message"', (tester) async {
      final repository = FakeAuthRepository()..signInError = error;
      final container = await _pumpLogin(tester, repository);

      await _tapGoogle(tester);

      expect(find.text(message), findsOneWidget);
      expect(container.read(authStateProvider), const AuthSignedOut());
    });
  }

  testWidgets('an unexpected Google plugin error shows a friendly message',
      (tester) async {
    final repository = FakeAuthRepository()
      ..signInError = PlatformException(code: 'sign_in_failed');
    final container = await _pumpLogin(tester, repository);

    await _tapGoogle(tester);

    expect(find.text(kGoogleSignInFailedMessage), findsOneWidget);
    expect(container.read(authStateProvider), const AuthSignedOut());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a retry clears the previous error', (tester) async {
    final repository = FakeAuthRepository()
      ..signInError = const NetworkException()
      ..signInUser = null;
    await _pumpLogin(tester, repository);
    await _tapGoogle(tester);

    repository.signInError = null;
    await _tapGoogle(tester);

    expect(find.text('Koneksi bermasalah. Coba lagi.'), findsNothing);
  });

  group('SesiBerakhir overlay', () {
    testWidgets('appears after an unauthorized event', (tester) async {
      final repository = FakeAuthRepository(restoredUser: testUser);
      final container = await _pumpLogin(tester, repository);
      expect(find.text('Sesi desamu sudah berakhir'), findsNothing);

      container.read(unauthorizedEventsProvider).notify();
      await tester.pumpAndSettle();

      expect(find.text('Sesi desamu sudah berakhir'), findsOneWidget);
      expect(find.text('HTTP 401'), findsOneWidget);
    });

    testWidgets('"Masuk lagi" hides it and starts the Google sign-in',
        (tester) async {
      final repository = FakeAuthRepository(restoredUser: testUser);
      final container = await _pumpLogin(tester, repository);
      container.read(unauthorizedEventsProvider).notify();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Masuk lagi'));
      await tester.pumpAndSettle();

      expect(find.text('Sesi desamu sudah berakhir'), findsNothing);
      expect(repository.signInCalls, 1);
      expect(container.read(authStateProvider), const AuthSignedIn(testUser));
    });

    testWidgets('a double tap on "Masuk lagi" starts one sign-in',
        (tester) async {
      final repository = FakeAuthRepository(restoredUser: testUser)
        ..signInGate = Completer<void>();
      final container = await _pumpLogin(tester, repository);
      container.read(unauthorizedEventsProvider).notify();
      await tester.pumpAndSettle();

      // Both taps land before the overlay is rebuilt away.
      await tester.tap(find.text('Masuk lagi'));
      await tester.tap(find.text('Masuk lagi'));
      await tester.pump();
      // The Google button is disabled while the sign-in runs.
      await tester.tap(
        find.byKey(const Key('google-sign-in')),
        warnIfMissed: false,
      );
      await tester.pump();

      repository.signInGate!.complete();
      await tester.pumpAndSettle();

      expect(repository.signInCalls, 1);
      expect(container.read(authStateProvider), const AuthSignedIn(testUser));
    });
  });
}
