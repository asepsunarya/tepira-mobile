// Independent edge cases: repeated taps on the Login screen during sign-in.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/auth/auth_repository.dart';
import 'package:tepira_mobile/features/auth/auth_providers.dart';
import 'package:tepira_mobile/features/auth/login_screen.dart';

import '../../helpers/fake_auth_repository.dart';

Future<ProviderContainer> _pump(
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

final _google = find.byKey(const Key('google-sign-in'));

void main() {
  testWidgets('rapid taps on the Google button open one picker',
      (tester) async {
    final repository = FakeAuthRepository()..signInGate = Completer<void>();
    final container = await _pump(tester, repository);

    // Three taps in the same frame, before any rebuild can disable it.
    await tester.tap(_google);
    await tester.tap(_google, warnIfMissed: false);
    await tester.tap(_google, warnIfMissed: false);
    await tester.pump();
    await tester.tap(_google, warnIfMissed: false);
    await tester.pump();

    repository.signInGate!.complete();
    await tester.pumpAndSettle();

    expect(repository.signInCalls, 1);
    expect(container.read(authStateProvider), const AuthSignedIn(testUser));
  });

  testWidgets('the button works again after a failed sign-in', (tester) async {
    final repository = FakeAuthRepository()
      ..signInError = const NetworkException();
    final container = await _pump(tester, repository);

    await tester.tap(_google);
    await tester.pumpAndSettle();
    expect(find.text('Koneksi bermasalah. Coba lagi.'), findsOneWidget);

    repository.signInError = null;
    await tester.tap(_google);
    await tester.pumpAndSettle();

    expect(repository.signInCalls, 2);
    expect(container.read(authStateProvider), const AuthSignedIn(testUser));
  });

  testWidgets('the button works again after a cancelled picker',
      (tester) async {
    final repository = FakeAuthRepository()..signInUser = null;
    await _pump(tester, repository);

    await tester.tap(_google);
    await tester.pumpAndSettle();
    await tester.tap(_google);
    await tester.pumpAndSettle();

    expect(repository.signInCalls, 2);
  });

  testWidgets('leaving the screen mid sign-in does not throw', (tester) async {
    final repository = FakeAuthRepository()
      ..signInGate = Completer<void>()
      ..signInError = const NetworkException();
    await _pump(tester, repository);

    await tester.tap(_google);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    repository.signInGate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
