import 'dart:async';

/// Runs [action] in a zone that adds its uncaught errors of type [T] to
/// [errors] instead of failing the test.
///
/// An async handler started by a tap inside [action] (a save that throws
/// something its code does not catch) keeps running in that zone, so an
/// error it throws later, after a gate completes, still lands in [errors].
///
/// Only [T] is collected. An uncaught error of any other type is passed on
/// to the enclosing zone, so it fails the test as usual. An error thrown by
/// [action] itself (a finder that matches nothing, a failed `expect`) is
/// never collected: it is rethrown to the caller, whatever its type.
///
/// [T] must be given explicitly and be narrower than [Object], so that an
/// unrelated error is never swallowed by accident.
Future<void> collectUncaught<T extends Object>(
  List<Object> errors,
  Future<void> Function() action,
) async {
  if (T == Object) {
    throw ArgumentError(
      'collectUncaught needs the expected error type, e.g. '
      'collectUncaught<FormatException>(...).',
    );
  }
  // Created in the caller's zone, so awaiting it is not cut off by the
  // error-zone boundary of the guarded zone below.
  final done = Completer<void>();
  runZonedGuarded(
    () async {
      try {
        await action();
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      }
    },
    (error, stack) {
      if (error is T) {
        errors.add(error);
        return;
      }
      // Thrown from the handler, it goes to the enclosing zone's handler.
      Error.throwWithStackTrace(error, stack);
    },
  );
  await done.future;
}
