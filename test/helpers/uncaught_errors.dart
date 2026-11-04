import 'dart:async';

/// Runs [action] in a zone that adds its uncaught errors to [errors]
/// instead of failing the test.
///
/// An async handler started by a tap inside [action] (a save that throws
/// something its code does not catch) keeps running in that zone, so an
/// error it throws later, after a gate completes, still lands in [errors].
Future<void> collectUncaught(
  List<Object> errors,
  Future<void> Function() action,
) async {
  await runZonedGuarded(action, (error, _) => errors.add(error));
}
