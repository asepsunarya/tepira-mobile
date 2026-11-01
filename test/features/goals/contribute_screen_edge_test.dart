import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tepira_mobile/core/errors.dart';
import 'package:tepira_mobile/core/routes.dart';
import 'package:tepira_mobile/core/theme.dart';
import 'package:tepira_mobile/core/widgets/village_button.dart';
import 'package:tepira_mobile/core/widgets/village_chip.dart';
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/goals/contribute_screen.dart';
import 'package:tepira_mobile/features/goals/goal_providers.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';

import '../../helpers/fake_goals_repository.dart';

/// [FakeGoalsRepository] that records [contribute] calls. The call with
/// index i throws `contributeErrors[i]` when that entry is not null.
class _Repo extends FakeGoalsRepository {
  _Repo({
    List<Object>? listResults,
    super.detailResults,
    this.contributeErrors = const [],
  }) : super(listResults ?? [_goals]);

  final List<Exception?> contributeErrors;
  final List<(int, int, String?)> contributions = [];
  Completer<void>? contributeGate;

  @override
  Future<void> contribute(int goalId, int amount, [String? note]) async {
    final call = contributions.length;
    contributions.add((goalId, amount, note));
    await contributeGate?.future;
    final error =
        call < contributeErrors.length ? contributeErrors[call] : null;
    if (error != null) throw error;
  }
}

final List<Goal> _goals = [
  testGoal(id: 1, title: 'Dana darurat'),
  testGoal(id: 2, title: 'Sepeda', saved: 0),
];

GoalDetail _detail(int id, List<Contribution> contributions) => GoalDetail(
      goal: testGoal(id: id, title: id == 1 ? 'Dana darurat' : 'Sepeda'),
      contributions: contributions,
    );

final Contribution _stored = Contribution(
  id: 41,
  amount: 20000,
  note: 'gajian',
  date: DateTime.utc(2026, 11, 1, 7),
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Repo repository, {
  String location = '/record?goal=1',
  bool direct = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: direct ? location : '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('desa')),
      ),
      GoRoute(
        path: GoalRoutes.detailPattern,
        builder: (context, state) =>
            Scaffold(body: Text('kavling ${state.uri}')),
      ),
      GoRoute(
        path: GoalRoutes.record,
        builder: (context, state) => ContributeScreen(
          goalParam: state.uri.queryParameters[GoalRoutes.recordGoalParam],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [goalsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  if (!direct) unawaited(router.push(location));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return container;
}

String _amount(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('amount'))).data!;

String _cta(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('submit')),
        matching: find.byType(Text),
      ),
    )
    .data!;

bool _ctaEnabled(WidgetTester tester) =>
    tester.widget<VillageButton>(find.byKey(const Key('submit'))).onPressed !=
    null;

bool _chipSelected(WidgetTester tester, int amount) =>
    tester.widget<VillageChip>(find.byKey(Key('chip-$amount'))).selected;

Future<void> _key(WidgetTester tester, String key, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(Key('key-$key')));
    await tester.pump();
  }
}

Future<void> _chip(WidgetTester tester, int amount) async {
  await tester.tap(find.byKey(Key('chip-$amount')));
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('submit')));
  await tester.pumpAndSettle();
}

void main() {
  group('?goal= parsing', () {
    for (final raw in [
      '2147483648', // int32 max + 1
      '99999999999999999999999', // overflows int64
      '-2',
      '2.0',
      '1e1',
      ' 2',
      '2 ',
      '٢', // Arabic-Indic digit two
      '3', // valid id, not in the list
      '2147483647', // int32 max, not in the list
    ]) {
      testWidgets('?goal=$raw does not preselect a goal', (tester) async {
        final repository = _Repo();
        await _pump(
          tester,
          repository,
          location: '/record?goal=${Uri.encodeQueryComponent(raw)}',
        );
        await _chip(tester, 20000);

        expect(find.text('Pilih kavling'), findsOneWidget);
        expect(
          find.text('Kavling dari tautan tidak ditemukan.'),
          findsOneWidget,
        );
        expect(_cta(tester), 'Pilih kavling dulu');
        expect(_ctaEnabled(tester), isFalse);
        await tester.tap(find.byKey(const Key('submit')));
        await tester.pump();
        expect(repository.contributions, isEmpty);
      });
    }

    for (final (raw, title) in [('02', 'Sepeda'), ('0001', 'Dana darurat')]) {
      testWidgets('?goal=$raw with leading zeros selects $title',
          (tester) async {
        final repository = _Repo();
        await _pump(tester, repository, location: '/record?goal=$raw');
        expect(find.text(title), findsOneWidget);
        expect(find.text('Kavling dari tautan tidak ditemukan.'), findsNothing);

        await _chip(tester, 10000);
        await _submit(tester);
        expect(repository.contributions.single.$1, int.parse(raw));
      });
    }

    testWidgets('?goal= of a missing goal: picking one clears the notice',
        (tester) async {
      await _pump(tester, _Repo(), location: '/record?goal=7');
      expect(find.text('Kavling dari tautan tidak ditemukan.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('goal-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-1')));
      await tester.pumpAndSettle();

      expect(find.text('Dana darurat'), findsOneWidget);
      expect(find.text('Kavling dari tautan tidak ditemukan.'), findsNothing);
    });

    testWidgets('?goal= with an empty goal list says there are none',
        (tester) async {
      await _pump(
        tester,
        _Repo(listResults: [const <Goal>[]]),
        location: '/record?goal=1',
      );
      expect(find.text('Belum ada kavling'), findsOneWidget);
      expect(_ctaEnabled(tester), isFalse);
    });
  });

  group('keypad cap at Rp999.999.999', () {
    testWidgets('typing up to the cap, then 0, 000 and 9 are ignored',
        (tester) async {
      await _pump(tester, _Repo());
      await _key(tester, '9', 9);
      expect(_amount(tester), 'Rp999.999.999');

      await _key(tester, '0');
      await _key(tester, '000');
      await _key(tester, '9');
      expect(_amount(tester), 'Rp999.999.999');
      expect(_cta(tester), 'Setor Rp999.999.999');
    });

    testWidgets('000 that fits lands, 000 that would pass the cap is dropped',
        (tester) async {
      await _pump(tester, _Repo());
      await _key(tester, '9', 6);
      await _key(tester, '000');
      expect(_amount(tester), 'Rp999.999.000');
      await _key(tester, '000');
      expect(_amount(tester), 'Rp999.999.000');
      // Nine digits already: one more would pass the cap.
      await _key(tester, '1');
      expect(_amount(tester), 'Rp999.999.000');

      await _key(tester, '⌫', 3);
      expect(_amount(tester), 'Rp999.999');
      await _key(tester, '000');
      expect(_amount(tester), 'Rp999.999.000');
    });

    testWidgets('chip then 000 twice goes over the cap only once',
        (tester) async {
      await _pump(tester, _Repo());
      await _chip(tester, 100000);
      await _key(tester, '000');
      expect(_amount(tester), 'Rp100.000.000');
      await _key(tester, '000');
      expect(_amount(tester), 'Rp100.000.000');
    });

    testWidgets('backspace from the cap down to 0 disables submit',
        (tester) async {
      final repository = _Repo();
      await _pump(tester, repository);
      await _key(tester, '9', 9);
      await _key(tester, '⌫', 9);
      expect(_amount(tester), 'Rp0');
      expect(_cta(tester), 'Isi nominal dulu');
      expect(_ctaEnabled(tester), isFalse);
      await _key(tester, '⌫');
      expect(_amount(tester), 'Rp0');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      expect(repository.contributions, isEmpty);
    });

    testWidgets('the cap amount is what gets deposited', (tester) async {
      final repository = _Repo();
      await _pump(tester, repository);
      await _key(tester, '9', 12);
      await _submit(tester);
      expect(repository.contributions, [(1, 999999999, null)]);
    });
  });

  group('chips and keypad', () {
    testWidgets('keypad extends a chip amount and deselects the chip',
        (tester) async {
      await _pump(tester, _Repo());
      await _chip(tester, 50000);
      expect(_chipSelected(tester, 50000), isTrue);

      await _key(tester, '000');
      expect(_amount(tester), 'Rp50.000.000');
      expect(_chipSelected(tester, 50000), isFalse);
    });

    testWidgets('a chip replaces a typed amount, not adds to it',
        (tester) async {
      await _pump(tester, _Repo());
      await _key(tester, '7');
      await _key(tester, '000');
      await _chip(tester, 10000);
      expect(_amount(tester), 'Rp10.000');
      expect(_chipSelected(tester, 10000), isTrue);
    });

    testWidgets('typing the chip amount by hand selects that chip',
        (tester) async {
      await _pump(tester, _Repo());
      await _key(tester, '2');
      await _key(tester, '0');
      await _key(tester, '000');
      expect(_amount(tester), 'Rp20.000');
      expect(_chipSelected(tester, 20000), isTrue);
    });

    testWidgets('backspacing a chip amount to 0 then a chip again',
        (tester) async {
      final repository = _Repo();
      await _pump(tester, repository);
      await _chip(tester, 10000);
      await _key(tester, '⌫', 5);
      expect(_amount(tester), 'Rp0');
      expect(_ctaEnabled(tester), isFalse);
      await _chip(tester, 100000);
      await _submit(tester);
      expect(repository.contributions, [(1, 100000, null)]);
    });

    testWidgets('changing the amount clears a rejection message',
        (tester) async {
      await _pump(
        tester,
        _Repo(contributeErrors: [const ApiException('Nominal tidak valid')]),
      );
      await _chip(tester, 20000);
      await _submit(tester);
      expect(find.byKey(const Key('submit-error')), findsOneWidget);
      await _key(tester, '0');
      expect(find.byKey(const Key('submit-error')), findsNothing);
    });
  });

  group('note', () {
    for (final note in ['\t', '\n', '   ', '　']) {
      testWidgets('whitespace-only note ${note.codeUnits} is sent as null',
          (tester) async {
        final repository = _Repo();
        await _pump(tester, repository);
        await _chip(tester, 10000);
        await tester.enterText(find.byKey(const Key('note')), note);
        await _submit(tester);
        expect(repository.contributions, [(1, 10000, null)]);
      });
    }

    testWidgets('note is capped at 120 characters', (tester) async {
      final repository = _Repo();
      await _pump(tester, repository);
      await _chip(tester, 10000);
      await tester.enterText(find.byKey(const Key('note')), 'a' * 200);
      await _submit(tester);
      expect(repository.contributions.single.$3, 'a' * 120);
    });

    testWidgets('inner whitespace is kept, outer trimmed', (tester) async {
      final repository = _Repo();
      await _pump(tester, repository);
      await _chip(tester, 10000);
      await tester.enterText(find.byKey(const Key('note')), '  uang  jajan ');
      await _submit(tester);
      expect(repository.contributions.single.$3, 'uang  jajan');
    });
  });

  group('submit disabled', () {
    testWidgets('while the goal list loads', (tester) async {
      final repository = _Repo()..listGate = Completer<void>();
      await _pump(tester, repository, settle: false);
      expect(find.text('Memuat kavling…'), findsOneWidget);
      await _chip(tester, 20000);
      expect(_cta(tester), 'Pilih kavling dulu');
      expect(_ctaEnabled(tester), isFalse);

      repository.listGate!.complete();
      await tester.pumpAndSettle();
      expect(_cta(tester), 'Setor Rp20.000');
      expect(_ctaEnabled(tester), isTrue);
    });

    testWidgets('when the goal list fails; tapping the field retries',
        (tester) async {
      final repository = _Repo(
        listResults: [const NetworkException(), _goals],
      );
      await _pump(tester, repository);
      expect(find.text('Daftar kavling gagal dimuat'), findsOneWidget);
      await _chip(tester, 20000);
      expect(_ctaEnabled(tester), isFalse);

      await tester.tap(find.byKey(const Key('goal-picker')));
      await tester.pumpAndSettle();
      expect(find.text('Dana darurat'), findsOneWidget);
      expect(_ctaEnabled(tester), isTrue);
    });

    testWidgets('while submitting, every input is locked', (tester) async {
      final repository = _Repo()..contributeGate = Completer<void>();
      await _pump(tester, repository);
      await _chip(tester, 20000);
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();

      expect(_cta(tester), 'Menyimpan…');
      expect(_ctaEnabled(tester), isFalse);
      await _chip(tester, 100000);
      await _key(tester, '5');
      expect(_amount(tester), 'Rp20.000');
      expect(
        tester.widget<TextField>(find.byKey(const Key('note'))).enabled,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('goal-picker')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pick-2')), findsNothing);

      repository.contributeGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.contributions, [(1, 20000, null)]);
    });
  });

  group('double tap guard', () {
    testWidgets('retry after a network failure is also guarded',
        (tester) async {
      final repository = _Repo(
        detailResults: [
          _detail(1, [_stored]),
        ],
        contributeErrors: [const NetworkException()],
      );
      await _pump(tester, repository);
      await _chip(tester, 20000);
      await _submit(tester);
      expect(_cta(tester), 'Setor Rp20.000 lagi');

      repository.contributeGate = Completer<void>();
      await tester.tap(find.byKey(const Key('submit')));
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      repository.contributeGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.contributions, hasLength(2));
    });
  });

  group('success', () {
    testWidgets('refreshes the picked goal detail and the goal list',
        (tester) async {
      final repository = _Repo(
        detailResults: [
          _detail(2, const []),
          _detail(2, [_stored]),
        ],
      );
      final container = await _pump(tester, repository);
      container.listen(goalDetailProvider(2), (_, __) {});
      container.listen(goalsProvider, (_, __) {});
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('goal-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-2')));
      await tester.pumpAndSettle();
      final listCalls = repository.listCalls;
      await _chip(tester, 50000);
      await _submit(tester);

      expect(repository.contributions, [(2, 50000, null)]);
      expect(repository.detailIds, [2, 2]);
      expect(repository.listCalls, listCalls + 1);
      expect(
        container.read(goalDetailProvider(2)).value!.contributions,
        [_stored],
      );
      expect(find.text('Setoran Rp50.000 masuk ke Sepeda.'), findsOneWidget);
    });

    testWidgets('opened directly with a picked goal lands on /goal/<picked>',
        (tester) async {
      await _pump(tester, _Repo(), location: '/record', direct: true);
      await tester.tap(find.byKey(const Key('goal-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-2')));
      await tester.pumpAndSettle();
      await _chip(tester, 10000);
      await _submit(tester);

      expect(find.text('kavling /goal/2'), findsOneWidget);
      expect(find.text('Setoran Rp10.000 masuk ke Sepeda.'), findsOneWidget);
    });

    testWidgets('close button opened directly goes to the Desa',
        (tester) async {
      await _pump(tester, _Repo(), direct: true);
      await tester.tap(find.bySemanticsLabel('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('desa'), findsOneWidget);
    });
  });

  group('network failure', () {
    testWidgets('reload fails repeatedly: card stays, no auto retry',
        (tester) async {
      final repository = _Repo(
        detailResults: [const NetworkException()],
        contributeErrors: [const NetworkException()],
      );
      await _pump(tester, repository);
      await _chip(tester, 20000);
      await _submit(tester);

      expect(find.byKey(const Key('uncertain-deposit')), findsOneWidget);
      expect(find.text('Koneksi terputus'), findsOneWidget);
      expect(find.text('Riwayat setoran belum bisa dimuat.'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('reload-latest')));
        await tester.pumpAndSettle();
        expect(find.text('Riwayat setoran belum bisa dimuat.'), findsOneWidget);
      }
      await tester.pump(const Duration(minutes: 5));
      expect(repository.contributions, hasLength(1));
      expect(repository.detailIds, [1, 1, 1, 1]);
      expect(_cta(tester), 'Setor Rp20.000 lagi');
      expect(_ctaEnabled(tester), isTrue);
      expect(find.byType(ContributeScreen), findsOneWidget);
    });

    testWidgets('goal list reload also fails: goal stays selected',
        (tester) async {
      final repository = _Repo(
        listResults: [_goals, const NetworkException()],
        detailResults: [const NetworkException()],
        contributeErrors: [const NetworkException()],
      );
      await _pump(tester, repository);
      await _chip(tester, 20000);
      await _submit(tester);

      expect(repository.listCalls, 2);
      expect(find.byKey(const Key('uncertain-deposit')), findsOneWidget);
      expect(find.text('Dana darurat'), findsOneWidget);
      expect(_cta(tester), 'Setor Rp20.000 lagi');
      expect(_ctaEnabled(tester), isTrue);
    });

    testWidgets('only the 3 latest deposits are listed, newest first',
        (tester) async {
      Contribution c(int id, int day) => Contribution(
            id: id,
            amount: id * 1000,
            note: null,
            date: DateTime.utc(2026, 10, day, 7),
          );
      final repository = _Repo(
        detailResults: [
          _detail(1, [c(1, 1), c(4, 4), c(2, 2), c(3, 3)]),
        ],
        contributeErrors: [const NetworkException()],
      );
      await _pump(tester, repository);
      await _chip(tester, 20000);
      await _submit(tester);

      expect(find.byKey(const Key('latest-1')), findsNothing);
      final ys = [4, 3, 2]
          .map((id) => tester.getTopLeft(find.byKey(Key('latest-$id'))).dy)
          .toList();
      expect(ys, orderedEquals([...ys]..sort()));
    });

    testWidgets('picking another goal clears the card and the "lagi"',
        (tester) async {
      final repository = _Repo(
        detailResults: [
          _detail(1, [_stored]),
        ],
        contributeErrors: [const NetworkException()],
      );
      await _pump(tester, repository);
      await _chip(tester, 20000);
      await _submit(tester);
      expect(find.byKey(const Key('uncertain-deposit')), findsOneWidget);

      await tester.tap(find.byKey(const Key('goal-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('uncertain-deposit')), findsNothing);
      expect(_cta(tester), 'Setor Rp20.000');
    });
  });

  group('gateway errors (coordinator decision: treat as network error)', () {
    group('BUG', () {
      for (final status in [502, 503, 504]) {
        testWidgets(
          '$status: no auto retry, goal reloaded, "Koneksi terputus" card, '
          '"Setor RpX lagi"',
          (tester) async {
            final repository = _Repo(
              detailResults: [
                _detail(1, [_stored]),
              ],
              contributeErrors: [ServerException(statusCode: status)],
            );
            await _pump(tester, repository);
            await _chip(tester, 20000);
            await _submit(tester);
            await tester.pump(const Duration(minutes: 1));

            expect(repository.contributions, hasLength(1));
            expect(repository.detailIds, [1]);
            expect(find.byKey(const Key('uncertain-deposit')), findsOneWidget);
            expect(find.text('Koneksi terputus'), findsOneWidget);
            expect(find.byKey(const Key('latest-41')), findsOneWidget);
            expect(find.byKey(const Key('submit-error')), findsNothing);
            expect(_cta(tester), 'Setor Rp20.000 lagi');
          },
        );
      }
    });

    for (final error in <AppException>[
      const ServerException(statusCode: 500),
      const ServerException(statusCode: 501),
      const ServerException(statusCode: 505),
      const ServerException(), // {ok:false} envelope, no status
      const ApiException('Nominal tidak valid', statusCode: 400),
      const ApiException('Terlalu besar', statusCode: 413),
      const ApiException('Terlalu sering', statusCode: 429),
      const NotFoundException(),
      const ForbiddenException(),
    ]) {
      testWidgets('$error stays "not recorded" with an inline message',
          (tester) async {
        final repository = _Repo(contributeErrors: [error]);
        await _pump(tester, repository);
        await _chip(tester, 20000);
        await _submit(tester);

        expect(find.text(error.message), findsOneWidget);
        expect(find.byKey(const Key('uncertain-deposit')), findsNothing);
        expect(repository.detailIds, isEmpty);
        expect(repository.contributions, hasLength(1));
        expect(_cta(tester), 'Setor Rp20.000');
      });
    }
  });
}
