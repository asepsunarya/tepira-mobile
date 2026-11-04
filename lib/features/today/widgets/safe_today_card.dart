import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/errors.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../core/wib.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../core/widgets/village_button.dart';
import '../../../core/widgets/village_card.dart';
import '../model/today_summary.dart';
import '../today_providers.dart';

/// The Desa block above the plots (SPEC-v2 §4 `today`): the "Aman dipakai
/// hari ini" card and the "Ditabung bulan ini" / "Jajan bulan ini" tiles.
/// Loading and errors stay inside the block, so a failed summary never hides
/// the plot list.
///
/// While shown it reloads the summary when the app comes back to the
/// foreground and when the WIB date changes (00:00 WIB by [clockProvider]),
/// so the card never shows yesterday's numbers as today's.
class TodaySection extends ConsumerStatefulWidget {
  const TodaySection({super.key});

  @override
  ConsumerState<TodaySection> createState() => _TodaySectionState();
}

class _TodaySectionState extends ConsumerState<TodaySection> {
  late final AppLifecycleListener _lifecycle;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _reload);
    _scheduleMidnight();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _scheduleMidnight() {
    final now = ref.read(clockProvider)();
    _midnight = Timer(wibDayStart(now, 1).difference(now), () {
      _reload();
      _scheduleMidnight();
    });
  }

  void _reload() => ref.invalidate(todayProvider);

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final summary = today.valueOrNull;
    if (summary != null && !today.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeTodayCard(summary: summary),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  key: const Key('saved-this-month'),
                  label: 'Ditabung bulan ini',
                  amount: summary.savedThisMonth,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  key: const Key('spent-this-month'),
                  label: 'Jajan bulan ini',
                  amount: summary.spentMonth,
                  tone: StatTone.spend,
                ),
              ),
            ],
          ),
        ],
      );
    }
    if (today.hasError && !today.isLoading) {
      return _TodayError(
        error: today.error!,
        onRetry: ref.read(todayProvider.notifier).refresh,
      );
    }
    return const _TodayLoading();
  }
}

/// "Aman dipakai hari ini" as the server sent it: the card reads
/// [SafeToday.state] and shows the server's numbers without recomputing
/// them. Over the month's budget it never says "aman".
class SafeTodayCard extends StatelessWidget {
  const SafeTodayCard({super.key, required this.summary});

  final TodaySummary summary;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final safe = summary.safeToday;
    final over = formatRupiah(safe.remaining.abs());
    final (String title, String amount, String? note) = switch (safe.state) {
      SafeTodayState.ok => (
          'Aman dipakai hari ini',
          formatRupiah(safe.remaining),
          safe.remaining == 0 ? 'Jatah hari ini sudah habis' : null,
        ),
      SafeTodayState.overToday => (
          'Aman dipakai hari ini',
          'Lewat $over hari ini',
          null,
        ),
      SafeTodayState.overMonth => (
          'Anggaran bulan ini sudah lewat',
          over,
          null
        ),
    };
    final red = safe.state != SafeTodayState.ok;
    final basis = switch ((safe.state, safe.basis)) {
      (SafeTodayState.overMonth, _) => null,
      (_, SafeTodayBasis.budget) =>
        'Jatah ${formatRupiah(safe.allowance)}/hari dari anggaran bulan ini',
      (_, SafeTodayBasis.wallet) => 'Dari uang bebas dibagi ${safe.days} hari '
          '(anggaran bulan ini belum diatur di web)',
    };
    return Semantics(
      container: true,
      label: [
        title,
        amount,
        if (note != null) note,
        if (basis != null) basis,
      ].join(', '),
      excludeSemantics: true,
      child: VillageCard(
        key: const Key('safe-today'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: villageText(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: red ? c.merah : c.redup,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                amount,
                key: const Key('safe-today-amount'),
                style: villageText(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: red ? c.merah : c.ink,
                ),
              ),
            ),
            if (note != null)
              Text(
                note,
                style: villageText(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: c.ink2,
                ),
              ),
            if (basis != null) ...[
              const SizedBox(height: 2),
              Text(basis, style: villageText(fontSize: 12, color: c.redup)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Still placeholder while the summary loads; it does not animate, so the
/// Desa can settle.
class _TodayLoading extends StatelessWidget {
  const _TodayLoading();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: c.track,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    return Semantics(
      label: 'Memuat angka hari ini',
      excludeSemantics: true,
      child: VillageCard(
        key: const Key('safe-today-loading'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(140, 12),
            const SizedBox(height: 8),
            bar(180, 28),
            const SizedBox(height: 8),
            bar(220, 12),
          ],
        ),
      ),
    );
  }
}

class _TodayError extends StatelessWidget {
  const _TodayError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final message = switch (error) {
      AppException(:final message) => message,
      _ => 'Ada yang tidak beres. Coba lagi.',
    };
    return VillageCard(
      key: const Key('safe-today-error'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Angka hari ini belum bisa dimuat',
            style: villageText(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(message, style: villageText(fontSize: 12, color: c.redup)),
          const SizedBox(height: 10),
          VillageButton(
            key: const Key('safe-today-retry'),
            label: 'Coba lagi',
            variant: VillageButtonVariant.soft,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
