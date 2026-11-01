import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/goals/goals_screen.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';
import 'package:tepira_mobile/features/goals/widgets/goal_row.dart';

import '../../helpers/fake_goals_repository.dart';

/// Independent edge cases for the Desa screen (T7, cdaf758).
Future<void> _pumpDesa(
  WidgetTester tester,
  FakeGoalsRepository repository, {
  String? userName = 'Asep',
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: GoalsScreen(userName: userName),
        ),
      ),
      GoRoute(
        path: '/goal/:id',
        builder: (context, state) => Text('page ${state.uri}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [goalsRepositoryProvider.overrideWithValue(repository)],
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
}

void main() {
  group('long text', () {
    final longTitle = 'Tabungan ${'sangat panjang sekali ' * 20}akhir';

    testWidgets('a very long goal name ellipsizes without overflow',
        (tester) async {
      await _pumpDesa(
        tester,
        FakeGoalsRepository([
          [testGoal(title: longTitle)],
        ]),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(GoalRow), findsOneWidget);
      final title = tester.widget<Text>(find.text(longTitle));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('a long unbroken name on a narrow screen does not overflow',
        (tester) async {
      await _pumpDesa(
        tester,
        FakeGoalsRepository([
          [testGoal(title: 'A' * 300)],
        ]),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('huge rupiah amounts on a narrow screen do not overflow',
        (tester) async {
      await _pumpDesa(
        tester,
        FakeGoalsRepository([
          [
            testGoal(
              title: 'Rumah',
              saved: 999999999999999,
              target: 1000000000000000,
            ),
          ],
        ]),
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('99%'), findsOneWidget);
    });

    testWidgets('long names at 2x text scale do not overflow', (tester) async {
      await _pumpDesa(
        tester,
        FakeGoalsRepository([
          [
            for (var i = 0; i < 6; i++)
              testGoal(id: i, title: '$longTitle $i', saved: i * 1000000),
          ],
        ]),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long user name ellipsizes in the HUD', (tester) async {
      final name = 'Asep ${'Sunandar ' * 30}';
      await _pumpDesa(
        tester,
        FakeGoalsRepository([
          [testGoal()],
        ]),
        userName: name,
      );
      expect(tester.takeException(), isNull);
      expect(find.text(name.trim()), findsOneWidget);
    });

    testWidgets('a whitespace-only or emoji user name is handled',
        (tester) async {
      await _pumpDesa(
        tester,
        FakeGoalsRepository([<Goal>[]]),
        userName: '   ',
      );
      expect(find.text('Warga desa'), findsOneWidget);
      expect(find.text('W'), findsOneWidget);
    });

    testWidgets('an emoji-first name shows the whole grapheme as avatar',
        (tester) async {
      await _pumpDesa(
        tester,
        FakeGoalsRepository([<Goal>[]]),
        userName: '👨‍👩‍👧 Keluarga',
      );
      expect(tester.takeException(), isNull);
      expect(find.text('👨‍👩‍👧'), findsOneWidget);
    });

    testWidgets('a long list of 50 goals scrolls to the last one',
        (tester) async {
      await _pumpDesa(
        tester,
        FakeGoalsRepository([
          [for (var i = 1; i <= 50; i++) testGoal(id: i, title: 'Goal $i')],
        ]),
      );
      await tester.scrollUntilVisible(find.text('Goal 50'), 300);
      expect(find.text('Goal 50'), findsOneWidget);
      await tester.tap(find.text('Goal 50'));
      await tester.pumpAndSettle();
      expect(find.text('page /goal/50'), findsOneWidget);
    });
  });

  group('error then retry', () {
    testWidgets('error, retry error, retry success', (tester) async {
      final goals = [testGoal(title: 'Dana darurat')];
      final repository = FakeGoalsRepository([
        const NetworkException(),
        const ServerException(statusCode: 503),
        goals,
      ]);
      await _pumpDesa(tester, repository);
      expect(find.text('Desa sedang offline'), findsOneWidget);

      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Balai Desa sedang tutup'), findsOneWidget);
      expect(find.text('Desa sedang offline'), findsNothing);

      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(repository.listCalls, 3);
      expect(find.text('Balai Desa sedang tutup'), findsNothing);
      expect(find.text('Dana darurat'), findsOneWidget);
    });

    testWidgets('pull to refresh on the error state recovers', (tester) async {
      final repository = FakeGoalsRepository([
        const NetworkException(),
        [testGoal(title: 'Laptop')],
      ]);
      await _pumpDesa(tester, repository);

      await tester.fling(
        find.text('Desa sedang offline'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Laptop'), findsOneWidget);
    });

    testWidgets('error then retry returning an empty list shows empty village',
        (tester) async {
      final repository = FakeGoalsRepository([
        const NetworkException(),
        <Goal>[],
      ]);
      await _pumpDesa(tester, repository);
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Desamu masih sepi'), findsOneWidget);
    });

    testWidgets('a list → failed refresh → retry restores the list',
        (tester) async {
      final repository = FakeGoalsRepository([
        [testGoal(title: 'Dana darurat')],
        const NetworkException(),
        [testGoal(title: 'Dana darurat'), testGoal(id: 2, title: 'Baru')],
      ]);
      await _pumpDesa(tester, repository);
      await tester.fling(find.text('Dana darurat'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Desa sedang offline'), findsOneWidget);

      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.byType(GoalRow), findsNWidgets(2));
    });

    testWidgets(
        'overlapping refreshes settle on the latest one even if an older '
        'request answers last', (tester) async {
      final repository = FakeGoalsRepository([
        <Goal>[],
        [testGoal(title: 'Jawaban lama')],
        [testGoal(title: 'Jawaban baru')],
      ]);
      await _pumpDesa(tester, repository);
      expect(find.text('Desamu masih sepi'), findsOneWidget);

      final older = repository.listCallGates[1] = Completer<void>();
      final newer = repository.listCallGates[2] = Completer<void>();
      final reload = find.text('Sudah punya data di tepira.id? Muat ulang');

      // The empty village stays on screen while refreshing, so the reload
      // button can really be tapped twice before either request answers.
      await tester.tap(reload);
      await tester.pump();
      expect(reload, findsOneWidget);
      await tester.tap(reload);
      await tester.pump();
      expect(repository.listCalls, 3);

      newer.complete();
      await tester.pumpAndSettle();
      expect(find.text('Jawaban baru'), findsOneWidget);

      older.complete();
      await tester.pumpAndSettle();
      expect(find.text('Jawaban baru'), findsOneWidget);
      expect(find.text('Jawaban lama'), findsNothing);
    });

    testWidgets('pull-to-refresh plus a reload tap: the later request wins',
        (tester) async {
      final repository = FakeGoalsRepository([
        <Goal>[],
        [testGoal(title: 'Dari tarikan')],
        [testGoal(title: 'Dari tombol')],
      ]);
      await _pumpDesa(tester, repository);

      final pulled = repository.listCallGates[1] = Completer<void>();
      final tapped = repository.listCallGates[2] = Completer<void>();

      await tester.fling(
        find.text('Desamu masih sepi'),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(repository.listCalls, 2);

      await tester.tap(find.text('Sudah punya data di tepira.id? Muat ulang'));
      await tester.pump();
      expect(repository.listCalls, 3);

      // The tap's request answers first; the pull's stale answer comes
      // later and must not overwrite it.
      tapped.complete();
      await tester.pumpAndSettle();
      expect(find.text('Dari tombol'), findsOneWidget);
      pulled.complete();
      await tester.pumpAndSettle();
      expect(find.text('Dari tombol'), findsOneWidget);
      expect(find.text('Dari tarikan'), findsNothing);
    });

    testWidgets('"Coba lagi" hides while loading, then shows the result',
        (tester) async {
      final repository = FakeGoalsRepository([
        const NetworkException(),
        [testGoal(title: 'Dana darurat')],
      ]);
      await _pumpDesa(tester, repository);

      repository.listGate = Completer<void>();
      await tester.tap(find.text('Coba lagi'));
      await tester.pump();
      // The button is gone while loading (skeleton), so it cannot be
      // tapped a second time.
      expect(find.text('Coba lagi'), findsNothing);
      repository.listGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.listCalls, 2);
      expect(find.text('Dana darurat'), findsOneWidget);
    });
  });
}
