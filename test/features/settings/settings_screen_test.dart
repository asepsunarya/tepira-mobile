import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/auth/auth_user.dart';
import 'package:tepira_mobile/features/settings/settings_screen.dart';

import '../../helpers/fake_auth_repository.dart';

Future<void> _pumpSettings(
  WidgetTester tester, {
  AuthUser user = testUser,
  required Future<void> Function() onSignOut,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildVillageTheme(),
      home: SettingsScreen(user: user, onSignOut: onSignOut),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
}

Future<void> _tapSignOut(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('sign-out')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the signed-in name, email and initial', (tester) async {
    await _pumpSettings(tester, onSignOut: () async {});

    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.text('Asep'), findsOneWidget);
    expect(find.text('asep@example.com'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('Keluar'), findsOneWidget);
  });

  testWidgets('a user without a name is shown as "Warga desa"', (tester) async {
    await _pumpSettings(
      tester,
      user: const AuthUser(id: 'u2', email: 'rina@example.com', name: '  '),
      onSignOut: () async {},
    );

    expect(find.text('Warga desa'), findsOneWidget);
    expect(find.text('rina@example.com'), findsOneWidget);
  });

  testWidgets('"Keluar" asks first; "Batal" keeps the session', (tester) async {
    var signOuts = 0;
    await _pumpSettings(tester, onSignOut: () async => signOuts++);

    await _tapSignOut(tester);
    expect(find.text('Keluar dari desa?'), findsOneWidget);
    expect(signOuts, 0);

    await tester.tap(find.byKey(const Key('cancel-sign-out')));
    await tester.pumpAndSettle();

    expect(find.text('Keluar dari desa?'), findsNothing);
    expect(signOuts, 0);
  });

  testWidgets('dismissing the dialog keeps the session', (tester) async {
    var signOuts = 0;
    await _pumpSettings(tester, onSignOut: () async => signOuts++);

    await _tapSignOut(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Keluar dari desa?'), findsNothing);
    expect(signOuts, 0);
  });

  testWidgets('confirming signs out once and disables the button meanwhile', (
    tester,
  ) async {
    final gate = Completer<void>();
    var signOuts = 0;
    await _pumpSettings(
      tester,
      onSignOut: () {
        signOuts++;
        return gate.future;
      },
    );

    await _tapSignOut(tester);
    await tester.tap(find.byKey(const Key('confirm-sign-out')));
    await tester.pumpAndSettle();
    expect(signOuts, 1);

    await _tapSignOut(tester);
    expect(find.text('Keluar dari desa?'), findsNothing);
    expect(signOuts, 1);
    gate.complete();
  });

  testWidgets('a failed sign-out shows a message and can be retried', (
    tester,
  ) async {
    var signOuts = 0;
    await _pumpSettings(
      tester,
      onSignOut: () async {
        signOuts++;
        throw Exception('keystore locked');
      },
    );

    await _tapSignOut(tester);
    await tester.tap(find.byKey(const Key('confirm-sign-out')));
    await tester.pumpAndSettle();

    expect(find.text(kSignOutFailedMessage), findsOneWidget);
    await _tapSignOut(tester);
    expect(find.text('Keluar dari desa?'), findsOneWidget);
    expect(signOuts, 1);
  });
}
