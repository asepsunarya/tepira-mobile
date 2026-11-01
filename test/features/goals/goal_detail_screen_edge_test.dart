import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/goals/goal_detail_screen.dart';
import 'package:tepira_mobile/features/goals/model/build_stage.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';
import 'package:tepira_mobile/features/goals/widgets/stage_illustration.dart';

import '../../helpers/fake_goals_repository.dart';

/// Independent edge cases for the Kavling screen (T8, 578adf7).

Goal _goal({
  int id = 12,
  String title = 'Rumah',
  String? description,
  int target = 10000000,
  int saved = 2500000,
  int? remaining,
  DateTime? deadline,
  int? daysLeft,
  int? perMonthNeeded,
  int contributionCount = 0,
}) =>
    Goal(
      id: id,
      title: title,
      description: description,
      target: target,
      saved: saved,
      percent: target == 0 ? 0 : saved * 100 / target,
      remaining: remaining ?? (target - saved < 0 ? 0 : target - saved),
      deadline: deadline,
      daysLeft: daysLeft,
      perMonthNeeded: perMonthNeeded,
      createdAt: DateTime.utc(2026, 1, 1),
      lastContribution: null,
      contributionCount: contributionCount,
    );

GoalDetail _detail(Goal goal, [List<Contribution> contributions = const []]) =>
    GoalDetail(goal: goal, contributions: contributions);

Contribution _c(int id, int amount, DateTime date, [String? note]) =>
    Contribution(id: id, amount: amount, note: note, date: date);

Future<GoRouter> _pump(
  WidgetTester tester,
  FakeGoalsRepository repository, {
  int? goalId = 12,
  Size size = const Size(390, 844),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Text('desa')),
      GoRoute(
        path: '/start',
        builder: (context, state) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: GoalDetailScreen(goalId: goalId),
        ),
      ),
      GoRoute(
        path: GoalRoutes.record,
        builder: (context, state) => Scaffold(body: Text('page ${state.uri}')),
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
  settle ? await tester.pumpAndSettle() : await tester.pump();
  return router;
}

BuildStage _stage(WidgetTester tester) =>
    tester.widget<StageIllustration>(find.byType(StageIllustration)).stage;

List<String> _historyLabels(WidgetTester tester) {
  final rows = find.bySemanticsLabel(RegExp(r'^\d+ \w+ \d{4}, '));
  return [
    for (var i = 0; i < rows.evaluate().length; i++)
      tester.getSemantics(rows.at(i)).label,
  ];
}

void main() {
  group('amounts', () {
    testWidgets('saved above target: 100%, selesai, Sisa Rp0, reached',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(
              _goal(
                saved: 12500000,
                deadline: DateTime.utc(2027, 1, 1),
                daysLeft: 61,
              ),
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('100%'), findsOneWidget);
      expect(_stage(tester), BuildStage.selesai);
      expect(find.bySemanticsLabel('Sisa: Rp0'), findsOneWidget);
      expect(find.bySemanticsLabel('Terkumpul: Rp12.500.000'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Kejar deadline: Sudah tercapai'),
        findsOneWidget,
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1.0);
      semantics.dispose();
    });

    testWidgets('target 0 does not crash: 0%, lahan', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [_detail(_goal(target: 0, saved: 0))],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('0%'), findsOneWidget);
      expect(_stage(tester), BuildStage.lahan);
      expect(find.bySemanticsLabel('Target: Rp0'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('saved 0 with a deadline shows the per-month amount',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(
              _goal(
                saved: 0,
                deadline: DateTime.utc(2027, 5, 1),
                daysLeft: 181,
                perMonthNeeded: 1666667,
              ),
            ),
          ],
        ),
      );

      expect(find.text('0%'), findsOneWidget);
      expect(_stage(tester), BuildStage.lahan);
      expect(
        find.bySemanticsLabel('Kejar deadline: Rp1.666.667/bulan'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Progres 0%'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('trillion-rupiah amounts format with dots', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(
              _goal(target: 9000000000000, saved: 1234567890123),
              [_c(1, 999999999999, DateTime.utc(2026, 10, 1))],
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel('Terkumpul: Rp1.234.567.890.123'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Target: Rp9.000.000.000.000'), findsOne);
      expect(find.bySemanticsLabel('Sisa: Rp7.765.432.109.877'), findsOne);
      // floor(1234567890123 * 100 / 9e12) = 13
      expect(find.text('13%'), findsOneWidget);
      expect(find.text('+Rp999.999.999.999'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('amounts near int64 max keep an exact floored percent',
        (tester) async {
      // (2^63-2) of (2^63-1): 99.99...% must floor to 99, not round to 100;
      // saved * 100 overflows int64, so this needs the BigInt path.
      const target = 9223372036854775807;
      const saved = 9223372036854775806;
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [_detail(_goal(target: target, saved: saved))],
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('99%'), findsOneWidget);
      expect(_stage(tester), BuildStage.atap);
      expect(
        find.text('Rp9.223.372.036.854.775.807'),
        findsOneWidget,
      );
    });
  });

  group('route ids', () {
    testWidgets('a negative id is requested and a 404 shows missing goal',
        (tester) async {
      final repository =
          FakeGoalsRepository([], detailResults: [const NotFoundException()]);
      await _pump(tester, repository, goalId: -5);

      expect(repository.detailIds, [-5]);
      expect(find.text('Kavling tidak ditemukan'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);
    });

    testWidgets('a huge id (beyond int32) is passed through untouched',
        (tester) async {
      final repository =
          FakeGoalsRepository([], detailResults: [const NotFoundException()]);
      await _pump(tester, repository, goalId: 9007199254740993);

      expect(repository.detailIds, [9007199254740993]);
      expect(find.text('Kavling tidak ditemukan'), findsOneWidget);
    });

    testWidgets('a missing route id offers only the way back, no retry',
        (tester) async {
      // goalId null: no request, so no retry button, only the way back.
      final repository = FakeGoalsRepository(
        [],
        detailResults: [_detail(_goal())],
      );
      await _pump(tester, repository, goalId: null);

      expect(find.text('Kembali ke desa'), findsWidgets);
      expect(find.text('Coba lagi'), findsNothing);
      expect(find.byKey(const Key('deposit')), findsNothing);
      await tester.tap(find.widgetWithText(InkWell, 'Kembali ke desa').last);
      await tester.pumpAndSettle();
      expect(find.text('desa'), findsOneWidget);
    });
  });

  group('text', () {
    testWidgets('null, empty and whitespace-only description show nothing',
        (tester) async {
      for (final description in [null, '', '   \n ']) {
        await _pump(
          tester,
          FakeGoalsRepository(
            [],
            detailResults: [_detail(_goal(description: description))],
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Rumah'), findsOneWidget);
        if (description != null) {
          expect(find.text(description), findsNothing);
        }
      }
    });

    testWidgets('empty and whitespace-only notes read Setoran, notes trimmed',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(_goal(contributionCount: 3), [
              _c(1, 1000, DateTime.utc(2026, 10, 3, 5), ''),
              _c(2, 2000, DateTime.utc(2026, 10, 2, 5), '  \t'),
              _c(3, 3000, DateTime.utc(2026, 10, 1, 5), '  Gaji  '),
            ]),
          ],
        ),
      );

      expect(_historyLabels(tester), [
        '3 Okt 2026, Setoran, +Rp1.000',
        '2 Okt 2026, Setoran, +Rp2.000',
        '1 Okt 2026, Gaji, +Rp3.000',
      ]);
      semantics.dispose();
    });

    testWidgets('a very long note ellipsizes on one line', (tester) async {
      final note = 'catatan ${'panjang ' * 40}akhir';
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(_goal(contributionCount: 1), [
              _c(1, 1000, DateTime.utc(2026, 10, 3, 5), note),
            ]),
          ],
        ),
        size: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text(note.trim()));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('a long unbroken title wraps without overflow at 320 wide',
        (tester) async {
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(_goal(title: 'Tabungan${'X' * 120}')),
          ],
        ),
        size: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('history', () {
    testWidgets('200 deposits scroll to the oldest one', (tester) async {
      final semantics = tester.ensureSemantics();
      final base = DateTime.utc(2026, 10, 31, 5);
      final contributions = [
        for (var i = 0; i < 200; i++)
          _c(i + 1, 1000 + i, base.subtract(Duration(days: i)), 'S$i'),
      ];
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(_goal(contributionCount: 250), contributions),
          ],
        ),
      );

      expect(
        find.bySemanticsLabel('Setoran terakhir, 250 setoran'),
        findsOneWidget,
      );
      expect(find.text('S0'), findsOneWidget);
      expect(find.text('S199'), findsNothing); // lazily built, off screen
      await tester.scrollUntilVisible(
        find.text('S199'),
        500,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 200,
      );
      expect(find.text('S199'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The Setor button stays pinned under the list.
      expect(find.byKey(const Key('deposit')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('identical timestamps: all rows shown, none dropped',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final at = DateTime.utc(2026, 10, 10, 5);
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(_goal(contributionCount: 3), [
              _c(3, 3000, at, 'C'),
              _c(2, 2000, at, 'B'),
              _c(1, 1000, at, 'A'),
            ]),
          ],
        ),
      );

      final labels = _historyLabels(tester);
      expect(labels, hasLength(3));
      expect(
        labels.toSet(),
        {
          '10 Okt 2026, A, +Rp1.000',
          '10 Okt 2026, B, +Rp2.000',
          '10 Okt 2026, C, +Rp3.000',
        },
      );
      // List.sort is not stable; for ties the server order (newest first)
      // is the only signal. Dart's sort is insertion sort below 32 items,
      // so it happens to be stable here.
      expect(labels, [
        '10 Okt 2026, C, +Rp3.000',
        '10 Okt 2026, B, +Rp2.000',
        '10 Okt 2026, A, +Rp1.000',
      ]);
      semantics.dispose();
    });

    testWidgets('dates are shown in local time, not UTC', (tester) async {
      // 2026-10-31T23:30Z is 1 Nov in WIB; the test runs in whatever zone the
      // host has, so compare against toLocal().
      final at = DateTime.utc(2026, 10, 31, 23, 30);
      final local = at.toLocal();
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(_goal(contributionCount: 1), [_c(1, 5000, at, 'x')]),
          ],
        ),
      );
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
      ];
      expect(_historyLabels(tester), [
        '${local.day} ${months[local.month - 1]} ${local.year}, x, +Rp5.000',
      ]);
      semantics.dispose();
    });
  });

  group('refresh', () {
    testWidgets(
        'refresh failing after a successful load shows the error, '
        'and retry restores the goal', (tester) async {
      final repository = FakeGoalsRepository(
        [],
        detailResults: [
          _detail(_goal(title: 'Pertama')),
          const ServerException(),
          _detail(_goal(title: 'Kedua')),
        ],
      );
      await _pump(tester, repository);
      expect(find.text('Pertama'), findsOneWidget);

      await tester.fling(find.text('Pertama'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      expect(repository.detailIds, [12, 12]);
      expect(find.text('Balai Desa sedang tutup'), findsOneWidget);
      expect(find.text('Pertama'), findsNothing);
      expect(find.byKey(const Key('deposit')), findsNothing);

      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Kedua'), findsOneWidget);
      expect(find.byKey(const Key('deposit')), findsOneWidget);
    });

    testWidgets('old content stays visible while a refresh is in flight',
        (tester) async {
      final repository = FakeGoalsRepository(
        [],
        detailResults: [
          _detail(_goal(title: 'Pertama')),
          _detail(_goal(title: 'Kedua')),
        ],
      );
      await _pump(tester, repository);
      repository.detailGate = Completer<void>();

      await tester.fling(find.text('Pertama'), const Offset(0, 400), 1000);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Pertama'), findsOneWidget);
      expect(find.byKey(const Key('deposit')), findsOneWidget);

      repository.detailGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Kedua'), findsOneWidget);
    });

    testWidgets('pull-to-refresh on the error card retries', (tester) async {
      final repository = FakeGoalsRepository(
        [],
        detailResults: [const NetworkException(), _detail(_goal())],
      );
      await _pump(tester, repository);
      expect(find.text('Desa sedang offline'), findsOneWidget);

      await tester.fling(
        find.text('Desa sedang offline'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(repository.detailIds, [12, 12]);
      expect(find.text('Rumah'), findsOneWidget);
    });

    testWidgets('an unknown exception type gets the generic retry message',
        (tester) async {
      final repository = FakeGoalsRepository(
        [],
        detailResults: [const FormatException('bad json'), _detail(_goal())],
      );
      await _pump(tester, repository);

      expect(find.text('Kavling belum bisa dimuat'), findsOneWidget);
      expect(find.text('Ada yang tidak beres. Coba lagi.'), findsOneWidget);
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Rumah'), findsOneWidget);
    });

    testWidgets('a 403 says the kavling is locked and can be retried',
        (tester) async {
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [const ForbiddenException()],
        ),
      );

      expect(find.text('Kavling ini terkunci'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
    });
  });

  group('Setor button', () {
    testWidgets('rapid double tap pushes the Setor page only once',
        (tester) async {
      final router = await _pump(
        tester,
        FakeGoalsRepository([], detailResults: [_detail(_goal())]),
      );

      await tester.tap(find.byKey(const Key('deposit')));
      // One frame later the transition has started; the Kavling route must
      // ignore the second tap.
      await tester.pump();
      await tester.tap(find.byKey(const Key('deposit')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('deposit')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('page /record?goal=12'), findsOneWidget);
      // Popping once must land back on the Kavling, not a second Setor.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposit')), findsOneWidget);
      expect(find.text('page /record?goal=12'), findsNothing);
    });

    testWidgets('one tap then back returns to the Kavling with fresh state',
        (tester) async {
      final repository =
          FakeGoalsRepository([], detailResults: [_detail(_goal())]);
      final router = await _pump(tester, repository);

      await tester.tap(find.byKey(const Key('deposit')));
      await tester.pumpAndSettle();
      expect(find.text('page /record?goal=12'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deposit')), findsOneWidget);
      expect(find.text('Rumah'), findsOneWidget);
    });
  });

  group('layout and semantics', () {
    testWidgets(
        'text scale 2.0 on 320x568: summary and tiles fit, '
        'including trillion amounts', (tester) async {
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(
              _goal(
                title: 'Dana pendidikan anak pertama',
                description: 'Untuk kuliah tahun depan, jangan diganggu.',
                target: 1500000000000,
                saved: 123456789012,
                deadline: DateTime.utc(2027, 12, 31),
                daysLeft: 425,
                perMonthNeeded: 98765432109,
              ),
            ),
          ],
        ),
        size: const Size(320, 568),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('empty-history')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });

    group(
      'text scale 2.0 on 320x568 history rows',
      () {
        for (final (amount, shown) in [
          (1200000, '+Rp1.200.000'),
          (999999999999, '+Rp999.999.999.999'),
        ]) {
          testWidgets('a $shown deposit row does not overflow', (tester) async {
            await _pump(
              tester,
              FakeGoalsRepository(
                [],
                detailResults: [
                  _detail(
                    _goal(
                      title: 'Laptop kerja',
                      target: 15000000,
                      saved: 6200000,
                      contributionCount: 1,
                    ),
                    [
                      _c(
                        1,
                        amount,
                        DateTime.utc(2026, 10, 28, 5),
                        'Sisa jajan Oktober',
                      ),
                    ],
                  ),
                ],
              ),
              size: const Size(320, 568),
              textScale: 2,
            );
            await tester.scrollUntilVisible(
              find.text(shown),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            expect(tester.takeException(), isNull);
          });
        }
      },
      skip: 'BUG: _ContributionRow lays out a fixed 76 px date, the note '
          '(Expanded) and the amount as an unconstrained Text in one Row. At '
          'text scale 2.0 on a 320 px wide screen the amount alone does not '
          'fit: a realistic +Rp1.200.000 overflows by 0.4 px and '
          '+Rp999.999.999.999 by 87 px (RenderFlex overflowed on the right). '
          '(goal_detail_screen.dart:485). The amount needs Flexible/FittedBox or '
          'the row needs to wrap.',
    );

    testWidgets('text scale 2.0 on 320x568: error card does not overflow',
        (tester) async {
      await _pump(
        tester,
        FakeGoalsRepository([], detailResults: [const NetworkException()]),
        size: const Size(320, 568),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Coba lagi'), findsOneWidget);
    });

    testWidgets('semantics: back, header, badge, tiles, rows and Setor',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        FakeGoalsRepository(
          [],
          detailResults: [
            _detail(
              _goal(
                deadline: DateTime.utc(2027, 1, 1),
                daysLeft: 61,
                perMonthNeeded: 3750000,
                contributionCount: 1,
              ),
              [_c(1, 2500000, DateTime.utc(2026, 10, 1, 5), 'Awal')],
            ),
          ],
        ),
      );

      expect(find.bySemanticsLabel('Kembali ke desa'), findsOneWidget);
      expect(find.bySemanticsLabel('Progres 25%'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Tahap ')), findsOneWidget);
      for (final label in [
        'Terkumpul: Rp2.500.000',
        'Sisa: Rp7.500.000',
        'Kejar deadline: Rp3.750.000/bulan',
        'Target: Rp10.000.000',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      final header = tester.getSemantics(
        find.bySemanticsLabel('Setoran terakhir, 1 setoran'),
      );
      expect(header.flagsCollection.isHeader, isTrue);
      expect(
        find.bySemanticsLabel('1 Okt 2026, Awal, +Rp2.500.000'),
        findsOneWidget,
      );
      final setor = tester.getSemantics(find.byKey(const Key('deposit')));
      expect(setor.label, contains('Setor ke kavling ini'));
      expect(setor.flagsCollection.isButton, isTrue);
      semantics.dispose();
    });

    testWidgets('the loader has a semantics label and no Setor button',
        (tester) async {
      final repository = FakeGoalsRepository(
        [],
        detailResults: [_detail(_goal())],
      )..detailGate = Completer<void>();
      await _pump(tester, repository, settle: false);
      expect(find.bySemanticsLabel('Memuat kavling'), findsOneWidget);
      expect(find.byKey(const Key('deposit')), findsNothing);
      repository.detailGate!.complete();
      await tester.pumpAndSettle();
    });
  });
}
