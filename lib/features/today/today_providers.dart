import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/today/today_repository.dart';
import 'model/today_summary.dart';

/// The Desa summary (`GET /api/mobile/today`). Disposed when no screen
/// watches it, so the next visit (or the next user) loads it fresh. The
/// Desa reloads it on resume and at 00:00 WIB (`TodaySection`).
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
  /// after the write, instead of reloading. If a load is in flight its GET
  /// may predate the write, so it is restarted: the newer numbers show now
  /// and the stale answer can never replace them.
  void applySummary(TodaySummary summary) {
    final loading = state.isLoading;
    state = AsyncData(summary);
    if (loading) ref.invalidateSelf();
  }
}

final todayProvider =
    AsyncNotifierProvider.autoDispose<TodayNotifier, TodaySummary>(
  TodayNotifier.new,
);
