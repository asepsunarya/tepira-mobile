import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/today/today_repository.dart';
import 'model/today_summary.dart';

/// The Desa summary (`GET /api/mobile/today`). Disposed when no screen
/// watches it, so the next visit (or the next user) loads it fresh.
class TodayNotifier extends AutoDisposeAsyncNotifier<TodaySummary> {
  @override
  Future<TodaySummary> build() => ref.watch(todayRepositoryProvider).get();

  /// Reloads the summary. A failure lands in the state as an error, not at
  /// the caller.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } on Object {
      // Already exposed as AsyncError in the state.
    }
  }

  /// Shows the `today` an expense write returned, computed by the server
  /// after the write, instead of reloading.
  void applySummary(TodaySummary summary) => state = AsyncData(summary);
}

final todayProvider =
    AsyncNotifierProvider.autoDispose<TodayNotifier, TodaySummary>(
  TodayNotifier.new,
);
