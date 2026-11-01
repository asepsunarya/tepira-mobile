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
import 'package:tepira_mobile/data/goals/goals_repository.dart';
import 'package:tepira_mobile/features/goals/goal_providers.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';
import 'package:tepira_mobile/features/goals/new_goal_screen.dart';

import '../../helpers/fake_goals_repository.dart';

typedef _CreateCall = ({
  String title,
  int target,
  String? description,
  DateTime? deadline,
});

class _CreatingRepository extends FakeGoalsRepository {
  _CreatingRepository({this.createResult}) : super([<Goal>[]]);

  Object? createResult;
  Completer<void>? createGate;
  final List<_CreateCall> createCalls = [];

  @override
  Future<Goal> create({
    required String title,
    required int target,
    String? description,
    DateTime? deadline,
  }) async {
    createCalls.add(
      (
        title: title,
        target: target,
        description: description,
        deadline: deadline,
      ),
    );
    await createGate?.future;
    final result = createResult ?? testGoal(id: 16, title: title);
    if (result is Exception) throw result;
    return result as Goal;
  }
}

class _Desa extends ConsumerWidget {
  const _Desa();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(goalsProvider);
    return const Text('desa');
  }
}

Future<GoRouter> _pump(WidgetTester tester, _CreatingRepository repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _Desa()),
      GoRoute(
        path: GoalRoutes.create,
        builder: (context, state) => const NewGoalScreen(),
      ),
      GoRoute(
        path: GoalRoutes.detailPattern,
        builder: (context, state) =>
            Text('kavling ${state.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [goalsRepositoryProvider.overrideWithValue(repo)],
      child:
          MaterialApp.router(theme: buildVillageTheme(), routerConfig: router),
    ),
  );
  await tester.runAsync(GoogleFonts.pendingFonts);
  await tester.pumpAndSettle();
  unawaited(router.push(GoalRoutes.create));
  await tester.pumpAndSettle();
  return router;
}

final _titleField = find.byKey(const Key('title'));
final _targetField = find.byKey(const Key('target'));
final _descField = find.byKey(const Key('description'));
final _submit = find.byKey(const Key('submit'));

String _fieldText(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _fill(
  WidgetTester tester, {
  String title = 'Kamera mirrorless',
  String target = '9000000',
  String? description,
}) async {
  await tester.enterText(_titleField, title);
  await tester.enterText(_targetField, target);
  if (description != null) await tester.enterText(_descField, description);
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(_submit);
  await tester.tap(_submit);
}

Future<void> _submitAndSettle(WidgetTester tester) async {
  await _tapSubmit(tester);
  await tester.pumpAndSettle();
}

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<VillageButton>(_submit).onPressed != null;

bool _fieldEnabled(WidgetTester tester, Finder field) =>
    tester
        .widget<TextField>(
          find.descendant(of: field, matching: find.byType(TextField)),
        )
        .enabled ??
    true;

Future<void> _pickDeadline(
  WidgetTester tester, {
  required int year,
  required int month,
  required int day,
}) async {
  await tester.tap(find.byKey(const Key('deadline')));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  final mm = '$month'.padLeft(2, '0');
  final dd = '$day'.padLeft(2, '0');
  await tester.enterText(
    find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)),
    '$mm/$dd/$year',
  );
  await tester.tap(find.text('Pilih'));
  await tester.pumpAndSettle();
}

void main() {
  group('name', () {
    testWidgets('exactly 60 characters is sent', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, title: 'a' * 60);
      await _submitAndSettle(tester);

      expect(repo.createCalls.single.title, 'a' * 60);
    });

    testWidgets('61 characters is rejected inline without calling the API',
        (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, title: 'a' * 61);
      await _submitAndSettle(tester);

      expect(find.text('Nama goal maksimal 60 karakter.'), findsOneWidget);
      expect(repo.createCalls, isEmpty);
    });

    testWidgets('60 chars padded with spaces is sent trimmed', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, title: '   ${'b' * 60}   ');
      await _submitAndSettle(tester);

      expect(repo.createCalls.single.title, 'b' * 60);
    });

    // Name length counts code points like the server (Array.from(title)).
    testWidgets(
      'a 31-emoji name (31 code points, 62 UTF-16 units) is sent',
      (tester) async {
        final repo = _CreatingRepository();
        await _pump(tester, repo);

        await _fill(tester, title: '🏠' * 31);
        await _submitAndSettle(tester);

        expect(find.text('Nama goal maksimal 60 karakter.'), findsNothing);
        expect(repo.createCalls.single.title, '🏠' * 31);
      },
    );

    testWidgets('a whitespace-only name (tabs/NBSP) is rejected',
        (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, title: ' \t  ');
      await _submitAndSettle(tester);

      expect(find.text('Nama goal harus diisi.'), findsOneWidget);
      expect(repo.createCalls, isEmpty);
    });

    testWidgets('a tab inside the name is rejected inline', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, title: 'Dana\tdarurat');
      await _submitAndSettle(tester);

      expect(
        find.text('Nama goal tidak boleh berisi karakter khusus.'),
        findsOneWidget,
      );
      expect(repo.createCalls, isEmpty);
    });

    testWidgets('a pasted newline never reaches the API', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, title: 'Dana\ndarurat');
      await _submitAndSettle(tester);

      // Either the single-line field drops it or the validator rejects it.
      for (final call in repo.createCalls) {
        expect(call.title.contains('\n'), isFalse);
      }
      if (repo.createCalls.isEmpty) {
        expect(
          find.text('Nama goal tidak boleh berisi karakter khusus.'),
          findsOneWidget,
        );
      }
    });
  });

  group('target field', () {
    testWidgets('2147483647 is accepted and sent as an int', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, target: '2147483647');
      expect(_fieldText(tester, _targetField), '2.147.483.647');
      await _submitAndSettle(tester);

      expect(repo.createCalls.single.target, 2147483647);
    });

    testWidgets('2147483648 is rejected as too big', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, target: '2147483648');
      await _submitAndSettle(tester);

      expect(find.text('Target terlalu besar.'), findsOneWidget);
      expect(repo.createCalls, isEmpty);
    });

    testWidgets('a 25-digit number is rejected, not crashing', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, target: '1' * 25);
      await _submitAndSettle(tester);

      expect(tester.takeException(), isNull);
      expect(repo.createCalls, isEmpty);
      expect(find.byType(NewGoalScreen), findsOneWidget);
    });

    testWidgets('leading zeros are dropped', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, target: '0001500');
      expect(_fieldText(tester, _targetField), '1.500');
      await _submitAndSettle(tester);

      expect(repo.createCalls.single.target, 1500);
    });

    testWidgets('all zeros collapses to 0 and is rejected', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, target: '0000');
      expect(_fieldText(tester, _targetField), '0');
      await _submitAndSettle(tester);

      expect(
        find.text('Target harus berupa angka bulat lebih dari 0.'),
        findsOneWidget,
      );
      expect(repo.createCalls, isEmpty);
    });

    for (final (paste, shown, sent) in [
      ('1.500.000', '1.500.000', 1500000),
      ('Rp 1.500.000', '1.500.000', 1500000),
      ('Rp1500000', '1.500.000', 1500000),
      ('1,500,000', '1.500.000', 1500000),
      (' 2 000 000 ', '2.000.000', 2000000),
      ('IDR 750.000', '750.000', 750000),
    ]) {
      testWidgets('pasting "$paste" shows $shown and sends $sent',
          (tester) async {
        final repo = _CreatingRepository();
        await _pump(tester, repo);

        await _fill(tester, target: paste);
        expect(_fieldText(tester, _targetField), shown);
        await _submitAndSettle(tester);

        expect(repo.createCalls.single.target, sent);
      });
    }

    testWidgets('pasting "Rp 1.500.000,-" sends 1500000', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, target: 'Rp 1.500.000,-');
      await _submitAndSettle(tester);

      expect(repo.createCalls.single.target, 1500000);
    });

    // Rupiah has no cents: a pasted decimal part (separator + 1-2 digits at
    // the end) is dropped instead of being glued onto the integer part.
    for (final (paste, shown, sent) in [
      ('Rp1.500.000,00', '1.500.000', 1500000),
      ('1.500.000,50', '1.500.000', 1500000),
      ('1500000.00', '1.500.000', 1500000),
      ('Rp 1.500.000,00,-', '1.500.000', 1500000),
      ('1,50', '1', 1),
    ]) {
      testWidgets('pasting "$paste" drops the decimal part and sends $sent',
          (tester) async {
        final repo = _CreatingRepository();
        await _pump(tester, repo);

        await _fill(tester, target: paste);
        expect(_fieldText(tester, _targetField), shown);
        await _submitAndSettle(tester);

        expect(repo.createCalls.single.target, sent);
      });
    }

    testWidgets('deleting the last digit only removes that digit',
        (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, target: '1500000');
      expect(_fieldText(tester, _targetField), '1.500.000');
      // Backspace leaves "1.500.00", which must not read as ",00" cents.
      await tester.enterText(_targetField, '1.500.00');
      expect(_fieldText(tester, _targetField), '150.000');
    });

    testWidgets('typing digits one by one groups them as before',
        (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      var shown = '';
      for (final (digit, expected) in [
        ('1', '1'),
        ('5', '15'),
        ('0', '150'),
        ('0', '1.500'),
        ('0', '15.000'),
      ]) {
        await tester.enterText(_targetField, '$shown$digit');
        shown = _fieldText(tester, _targetField);
        expect(shown, expected);
      }
    });
  });

  group('description', () {
    testWidgets('200 characters is sent, 201 is rejected', (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, description: 'd' * 201);
      await _submitAndSettle(tester);
      expect(find.text('Deskripsi maksimal 200 karakter.'), findsOneWidget);
      expect(repo.createCalls, isEmpty);

      await tester.enterText(_descField, 'd' * 200);
      await _submitAndSettle(tester);
      expect(repo.createCalls.single.description, 'd' * 200);
    });

    testWidgets('a whitespace-only description is sent as null',
        (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, description: ' \n\t \n');
      await _submitAndSettle(tester);

      expect(repo.createCalls.single.description, isNull);
    });

    testWidgets('a multi-line description keeps inner newlines',
        (tester) async {
      final repo = _CreatingRepository();
      await _pump(tester, repo);

      await _fill(tester, description: '\nbaris 1\nbaris 2\n');
      await _submitAndSettle(tester);

      expect(repo.createCalls.single.description, 'baris 1\nbaris 2');
    });
  });

  group('deadline', () {
    for (final (y, m, d) in [(2027, 1, 1), (2028, 2, 29), (2027, 12, 31)]) {
      testWidgets('picking $y-$m-$d passes that local calendar date',
          (tester) async {
        final repo = _CreatingRepository();
        await _pump(tester, repo);

        await _fill(tester);
        await _pickDeadline(tester, year: y, month: m, day: d);
        await _submitAndSettle(tester);

        final deadline = repo.createCalls.single.deadline!;
        expect(deadline.isUtc, isFalse);
        expect((deadline.year, deadline.month, deadline.day), (y, m, d));
        expect((deadline.hour, deadline.minute), (0, 0));
      });
    }
  });

  group('double submit', () {
    testWidgets('two taps in the same frame create once', (tester) async {
      final repo = _CreatingRepository()..createGate = Completer();
      await _pump(tester, repo);

      await _fill(tester);
      await tester.ensureVisible(_submit);
      await tester.tap(_submit);
      await tester.tap(_submit, warnIfMissed: false);
      await tester.pump();

      expect(repo.createCalls, hasLength(1));
      repo.createGate!.complete();
      await tester.pumpAndSettle();
      expect(repo.createCalls, hasLength(1));
      expect(repo.listCalls, 2);
    });

    testWidgets('fields and deadline are locked while saving', (tester) async {
      final repo = _CreatingRepository()..createGate = Completer();
      await _pump(tester, repo);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pump();

      expect(_submitEnabled(tester), isFalse);
      expect(_fieldEnabled(tester, _titleField), isFalse);
      expect(_fieldEnabled(tester, _targetField), isFalse);
      expect(_fieldEnabled(tester, _descField), isFalse);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('deadline')))
            .onPressed,
        isNull,
      );

      repo.createGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('leaving the screen while saving does not throw',
        (tester) async {
      final repo = _CreatingRepository()..createGate = Completer();
      final router = await _pump(tester, repo);

      await _fill(tester);
      await _tapSubmit(tester);
      await tester.pump();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('desa'), findsOneWidget);

      repo.createGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('desa'), findsOneWidget);
    });
  });

  group('error path resets state', () {
    for (final (name, error) in <(String, AppException)>[
      (
        '400 ServerException',
        const ServerException(
          message: 'Judul harus diisi, maksimal 60 karakter.',
          code: 'bad_request',
          statusCode: 400,
        ),
      ),
      ('400 ApiException', const ApiException('Bad', statusCode: 400)),
      ('500', const ServerException(statusCode: 500)),
      ('unknown ApiException', const ApiException('Permintaan gagal.')),
    ]) {
      testWidgets(
          'after $name: button and fields are re-enabled, input kept, '
          'retry clears the error and succeeds', (tester) async {
        final repo = _CreatingRepository(createResult: error);
        await _pump(tester, repo);

        await _fill(tester, title: 'Dana darurat', target: '1500000');
        await _submitAndSettle(tester);

        expect(find.byKey(const Key('submitError')), findsOneWidget);
        expect(find.text('Patok kavling'), findsOneWidget);
        expect(find.text('Mematok kavling…'), findsNothing);
        expect(_submitEnabled(tester), isTrue);
        expect(_fieldEnabled(tester, _titleField), isTrue);
        expect(_fieldEnabled(tester, _targetField), isTrue);
        expect(_fieldText(tester, _titleField), 'Dana darurat');
        expect(_fieldText(tester, _targetField), '1.500.000');
        expect(repo.listCalls, 1);

        // Retry: the old error disappears as soon as the retry starts.
        repo
          ..createResult = null
          ..createGate = Completer();
        await _tapSubmit(tester);
        await tester.pump();
        expect(find.byKey(const Key('submitError')), findsNothing);
        repo.createGate!.complete();
        await tester.pumpAndSettle();

        expect(repo.createCalls, hasLength(2));
        expect(find.text('kavling 16'), findsOneWidget);
      });
    }

    testWidgets(
        'a server error is cleared when a later submit fails '
        'client validation', (tester) async {
      final repo = _CreatingRepository(
        createResult: const ServerException(statusCode: 500),
      );
      await _pump(tester, repo);

      await _fill(tester);
      await _submitAndSettle(tester);
      expect(find.byKey(const Key('submitError')), findsOneWidget);

      await tester.enterText(_titleField, '');
      await _submitAndSettle(tester);

      expect(find.byKey(const Key('submitError')), findsNothing);
      expect(find.text('Nama goal harus diisi.'), findsOneWidget);
      expect(repo.createCalls, hasLength(1));
    });

    testWidgets('two failures in a row keep the button usable', (tester) async {
      final repo = _CreatingRepository(
        createResult: const ServerException(statusCode: 500),
      );
      await _pump(tester, repo);

      await _fill(tester);
      await _submitAndSettle(tester);
      await _submitAndSettle(tester);

      expect(repo.createCalls, hasLength(2));
      expect(_submitEnabled(tester), isTrue);
      expect(find.byKey(const Key('submitError')), findsOneWidget);
    });
  });
}
