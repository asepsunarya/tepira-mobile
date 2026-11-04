import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'uncaught_errors.dart';

/// Runs [action] and returns what it threw, or null when it completed.
Future<Object?> _thrownBy(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } catch (error) {
    return error;
  }
}

void main() {
  test('collects a later uncaught error of the expected type', () async {
    final errors = <Object>[];
    final later = Completer<void>();
    await collectUncaught<FormatException>(errors, () async {
      // Started inside the zone, failing after the action has completed.
      unawaited(
        later.future.then((_) => throw const FormatException('boom')),
      );
    });
    later.complete();
    await pumpEventQueue();
    expect(errors, [isA<FormatException>()]);
  });

  test('passes an uncaught error of another type on to the enclosing zone',
      () async {
    final errors = <Object>[];
    final outer = <Object>[];
    final later = Completer<void>();
    await runZonedGuarded(
      () => collectUncaught<FormatException>(errors, () async {
        unawaited(later.future.then((_) => throw StateError('unexpected')));
      }),
      (error, _) => outer.add(error),
    );
    later.complete();
    await pumpEventQueue();
    expect(errors, isEmpty);
    expect(outer, [isA<StateError>()]);
  });

  test('rethrows an error thrown by the action itself, even of the type',
      () async {
    final errors = <Object>[];
    final thrown = await _thrownBy(
      () => collectUncaught<FormatException>(
        errors,
        () async => throw const FormatException('boom'),
      ),
    );
    expect(thrown, isA<FormatException>());
    expect(errors, isEmpty);
  });

  test('refuses to run without an expected type', () async {
    final thrown = await _thrownBy(
      () => collectUncaught(<Object>[], () async {}),
    );
    expect(thrown, isA<ArgumentError>());
  });

  testWidgets('a tap whose finder matches nothing fails the caller',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('home')));
    final errors = <Object>[];
    final thrown = await _thrownBy(
      () => collectUncaught<FormatException>(
        errors,
        () => tester.tap(find.byKey(const Key('missing'))),
      ),
    );
    expect(thrown, isNotNull);
    expect(thrown, isNot(isA<FormatException>()));
    expect(errors, isEmpty);
  });

  testWidgets('a failed expect inside the action fails the caller',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('home')));
    final errors = <Object>[];
    final thrown = await _thrownBy(
      () => collectUncaught<FormatException>(errors, () async {
        expect(find.text('not there'), findsOneWidget);
      }),
    );
    expect(thrown, isA<TestFailure>());
    expect(errors, isEmpty);
  });
}
