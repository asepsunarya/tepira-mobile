import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/goals/goals_repository.dart';
import 'model/goal.dart';

/// The signed-in user's goals for the Desa screen, in server order.
/// Disposed when the screen goes away, so the next visit (or the next user)
/// loads a fresh list.
class GoalsNotifier extends AutoDisposeAsyncNotifier<List<Goal>> {
  @override
  Future<List<Goal>> build() => ref.watch(goalsRepositoryProvider).list();

  /// Reloads the list. Keeps showing the current goals while loading; a
  /// failure replaces them with the error.
  ///
  /// Rebuilds through Riverpod, so when refreshes overlap only the latest
  /// one lands, and nothing is written after the provider is disposed. The
  /// error stays in the state rather than being thrown at the caller.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } on Object {
      // Already exposed as AsyncError in the state.
    }
  }
}

final goalsProvider =
    AsyncNotifierProvider.autoDispose<GoalsNotifier, List<Goal>>(
  GoalsNotifier.new,
);
