import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/core/widgets/village_button.dart';
import 'package:tepira_mobile/data/auth/auth_user.dart';
import 'package:tepira_mobile/features/settings/settings_screen.dart';

import '../../helpers/fake_auth_repository.dart';

/// Pumps Pengaturan pushed on top of a stub home, so a stray extra pop is
/// visible as the stub coming back.
Future<void> _pumpSettings(
  WidgetTester tester, {
  AuthUser user = testUser,
  Future<void> Function()? onSignOut,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: buildVillageTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: const Scaffold(body: Text('home stub')),
    ),
  );
  unawaited(
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          user: user,
          onSignOut: onSignOut ?? () async {},
        ),
      ),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
}

/// The text inside the avatar.
Finder _initial() => find.descendant(
      of: find.byType(CircleAvatar),
      matching: find.byType(Text),
    );

String _initialText(WidgetTester tester) =>
    tester.widget<Text>(_initial()).data!;

void main() {
  group('name fallback and initial', () {
    for (final (label, name) in [
      ('null', null),
      ('empty', ''),
      ('tabs and newlines', '\t\n  \n'),
    ]) {
      testWidgets('a $label name shows "Warga desa" with initial W',
          (tester) async {
        await _pumpSettings(
          tester,
          user: AuthUser(id: 'u', email: 'x@example.com', name: name),
        );

        expect(find.text('Warga desa'), findsOneWidget);
        expect(_initialText(tester), 'W');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('surrounding whitespace is trimmed; initial is uppercased',
        (tester) async {
      await _pumpSettings(
        tester,
        user: const AuthUser(id: 'u', email: 'x@example.com', name: '  budi  '),
      );

      expect(find.text('budi'), findsOneWidget);
      expect(_initialText(tester), 'B');
    });

    for (final (label, name, initial) in [
      ('a ZWJ family emoji', '👨‍👩‍👧 Keluarga', '👨‍👩‍👧'),
      ('a flag emoji', '🇮🇩 Indah', '🇮🇩'),
      ('a skin-tone emoji', '👍🏽 Joko', '👍🏽'),
      ('a combining accent', 'élodie', 'É'),
      ('a non-Latin script', 'สมชาย', 'ส'),
    ]) {
      testWidgets('$label keeps the whole first grapheme as the initial',
          (tester) async {
        await _pumpSettings(
          tester,
          user: AuthUser(id: 'u', email: 'x@example.com', name: name),
        );

        expect(_initialText(tester), initial);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('overflow', () {
    const longUser = AuthUser(
      id: 'u',
      email: 'seorang.warga.desa.dengan.alamat.surel.yang.sangat.panjang.sekali'
          '@subdomain.contoh-domain-panjang.example.com',
      name: 'Raden Mas Bagus Wicaksono Adiningrat Kusumawardhana '
          'Prawiranegara Hadiningrat',
    );

    for (final scale in [1.0, 2.0]) {
      testWidgets('a long name and email fit 320px at text scale $scale',
          (tester) async {
        await _pumpSettings(
          tester,
          user: longUser,
          size: const Size(320, 640),
          textScale: scale,
        );

        expect(tester.takeException(), isNull);
        final name = tester.widget<Text>(find.text(longUser.name!));
        final email = tester.widget<Text>(find.text(longUser.email));
        expect(name.maxLines, 1);
        expect(name.overflow, TextOverflow.ellipsis);
        expect(email.maxLines, 1);
        expect(email.overflow, TextOverflow.ellipsis);
        // Both stay inside the screen.
        for (final text in [longUser.name!, longUser.email]) {
          final rect = tester.getRect(find.text(text));
          expect(rect.right, lessThanOrEqualTo(320));
        }
        expect(find.byKey(const Key('sign-out')), findsOneWidget);
      });
    }

    testWidgets('the confirm dialog fits 320px at text scale 2.0',
        (tester) async {
      await _pumpSettings(
        tester,
        size: const Size(320, 640),
        textScale: 2,
      );

      await tester.tap(find.byKey(const Key('sign-out')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('confirm-sign-out')), findsOneWidget);
      expect(find.byKey(const Key('cancel-sign-out')), findsOneWidget);
    });
  });

  group('photo', () {
    for (final (label, url) in [
      ('an unreachable URL', 'https://example.test/avatar/missing.png'),
      ('a malformed URL', 'not a url at all'),
      ('an empty URL', ''),
    ]) {
      testWidgets('$label falls back to the initial without an error',
          (tester) async {
        await _pumpSettings(
          tester,
          user: AuthUser(
            id: 'u',
            email: 'x@example.com',
            name: 'Sari',
            image: url,
          ),
        );
        // Let the image load fail for real (the test HttpClient answers 400).
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(_initialText(tester), 'S');
        expect(find.text('Sari'), findsOneWidget);
      });
    }

    testWidgets('a photo URL is used as the foreground image', (tester) async {
      await _pumpSettings(
        tester,
        user: const AuthUser(
          id: 'u',
          email: 'x@example.com',
          name: 'Sari',
          image: 'https://example.test/avatar/sari.png',
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(
        (avatar.foregroundImage! as NetworkImage).url,
        'https://example.test/avatar/sari.png',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('taps', () {
    testWidgets('double-tapping Keluar never stacks dialogs or signs out',
        (tester) async {
      var signOuts = 0;
      await _pumpSettings(tester, onSignOut: () async => signOuts++);

      await tester.tap(find.byKey(const Key('sign-out')));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      // The second tap lands on the modal barrier, which dismisses the
      // dialog (standard showDialog behaviour), so nothing is stacked.
      await tester.tap(find.byKey(const Key('sign-out')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog).evaluate().length, lessThanOrEqualTo(1));
      expect(signOuts, 0);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets(
        'double-tapping confirm signs out once and pops only the '
        'dialog', (tester) async {
      final gate = Completer<void>();
      var signOuts = 0;
      await _pumpSettings(
        tester,
        onSignOut: () {
          signOuts++;
          return gate.future;
        },
      );

      await tester.tap(find.byKey(const Key('sign-out')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const Key('confirm-sign-out'));
      await tester.tap(confirm);
      await tester.pump();
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(confirm, warnIfMissed: false);
      }
      await tester.pump(const Duration(milliseconds: 20));
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(confirm, warnIfMissed: false);
      }
      await tester.pumpAndSettle();

      expect(signOuts, 1);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('home stub'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Keluar stays disabled until a slow sign-out ends',
        (tester) async {
      final gate = Completer<void>();
      var signOuts = 0;
      await _pumpSettings(
        tester,
        onSignOut: () {
          signOuts++;
          return gate.future;
        },
      );

      await tester.tap(find.byKey(const Key('sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-sign-out')));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('sign-out')));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(AlertDialog), findsNothing);
      expect(signOuts, 1);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets(
        'back during a slow sign-out leaves without errors; a late '
        'failure is swallowed', (tester) async {
      final gate = Completer<void>();
      await _pumpSettings(tester, onSignOut: () => gate.future);

      await tester.tap(find.byKey(const Key('sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-sign-out')));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('home stub'), findsOneWidget);

      gate.completeError(Exception('keystore locked'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(kSignOutFailedMessage), findsNothing);
    });

    testWidgets('a failure then a success: message, retry, single call each',
        (tester) async {
      var calls = 0;
      await _pumpSettings(
        tester,
        onSignOut: () async {
          calls++;
          if (calls == 1) throw StateError('first try fails');
        },
      );

      Future<void> confirm() async {
        await tester.tap(find.byKey(const Key('sign-out')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-sign-out')));
        await tester.pumpAndSettle();
      }

      await confirm();
      expect(find.text(kSignOutFailedMessage), findsOneWidget);
      final button =
          tester.widget<VillageButton>(find.byKey(const Key('sign-out')));
      expect(button.onPressed, isNotNull);

      await confirm();
      expect(calls, 2);
    });
  });
}
