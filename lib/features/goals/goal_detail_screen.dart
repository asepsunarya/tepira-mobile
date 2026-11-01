import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import 'goal_providers.dart';
import 'model/build_stage.dart';
import 'model/display_percent.dart';
import 'model/goal.dart';
import 'widgets/stage_illustration.dart';

/// The Kavling screen (`/goal/:id`, artboard GoalDetail): the building stage,
/// amounts, deadline catch-up, deposit history and the Setor button.
/// Pull down to reload.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  /// Null when the route id is not a number; shown as a missing goal.
  final int? goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = VillageColors.of(context);
    final id = goalId;

    final Widget body;
    Widget? bottom;
    if (id == null) {
      body =
          const _Scrollable(children: [_LoadError(error: NotFoundException())]);
    } else {
      final detail = ref.watch(goalDetailProvider(id));
      final notifier = ref.read(goalDetailProvider(id).notifier);
      final value = detail.valueOrNull;
      if (value != null && !detail.hasError) {
        body = _Scrollable(
          onRefresh: notifier.refresh,
          children: _content(value),
        );
        bottom = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: VillageButton(
              key: const Key('deposit'),
              label: 'Setor ke kavling ini',
              onPressed: () => context.push(GoalRoutes.recordFor(id)),
            ),
          ),
        );
      } else if (detail.hasError && !detail.isLoading) {
        body = _Scrollable(
          onRefresh: notifier.refresh,
          children: [
            _LoadError(error: detail.error!, onRetry: notifier.refresh),
          ],
        );
      } else {
        body = const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Memuat kavling'),
        );
      }
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.langit, c.langitMuda, c.kertas],
            stops: const [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const _Header(),
              Expanded(child: body),
              if (bottom != null) bottom,
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(GoalDetail detail) {
    final contributions = [...detail.contributions]
      ..sort((a, b) => b.date.compareTo(a.date));
    return [
      _Summary(goal: detail.goal),
      const SizedBox(height: 12),
      _Stats(goal: detail.goal),
      const SizedBox(height: 12),
      _HistoryHeader(count: detail.goal.contributionCount),
      const SizedBox(height: 6),
      if (contributions.isEmpty)
        const _EmptyHistory()
      else
        for (final contribution in contributions) ...[
          _ContributionRow(contribution: contribution),
          const SizedBox(height: 6),
        ],
    ];
  }
}

/// Pull-to-refresh list that scrolls even when its content is short. Without
/// [onRefresh] it only scrolls.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.children, this.onRefresh});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: children,
    );
    final refresh = onRefresh;
    return refresh == null
        ? list
        : RefreshIndicator(onRefresh: refresh, child: list);
  }
}

/// Back button and the "Kavling" title.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final radius = BorderRadius.circular(16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Material(
            color: c.kartu.withValues(alpha: 0.9),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: c.putih, width: 2),
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: () => _backToDesa(context),
              child: SizedBox.square(
                dimension: 44,
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: c.ink,
                  semanticLabel: 'Kembali ke desa',
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Kavling',
              textAlign: TextAlign.center,
              style: villageText(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// Pops back, or opens the Desa when the Kavling was opened directly.
void _backToDesa(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

/// Card with the stage drawing, title, deadline, percent and progress bar.
class _Summary extends StatelessWidget {
  const _Summary({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final stage = buildStage(saved: goal.saved, target: goal.target);
    final percent = displayPercent(saved: goal.saved, target: goal.target);
    final description = goal.description?.trim();
    return VillageCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StageIllustration(stage: stage),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      style: villageText(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _deadlineText(goal),
                      style: villageText(fontSize: 12, color: c.redup),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                container: true,
                label: 'Progres $percent%',
                excludeSemantics: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.pinkSoft,
                    borderRadius: BorderRadius.circular(VillageRadius.pill),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      '$percent%',
                      style: villageText(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: c.pinkText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: villageText(fontSize: 12, color: c.ink2, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(VillageRadius.pill),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 10,
                color: stage == BuildStage.selesai ? c.mint : c.pink,
                backgroundColor: c.track,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Target 30 Apr 2027 · 180 hari lagi", or a note that there is no deadline.
String _deadlineText(Goal goal) {
  final deadline = goal.deadline;
  if (deadline == null) return 'Tanpa tenggat';
  final target = 'Target ${formatShortDate(deadline)}';
  return switch (goal.daysLeft) {
    null => target,
    0 => '$target · tenggat habis',
    final days => '$target · $days hari lagi',
  };
}

/// Two-by-two tiles: saved, remaining, catch-up per month and target.
class _Stats extends StatelessWidget {
  const _Stats({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final perMonth = goal.perMonthNeeded;
    final catchUp = switch (perMonth) {
      final amount? => '${formatRupiah(amount)}/bulan',
      null when goal.saved >= goal.target => 'Sudah tercapai',
      null when goal.deadline == null => 'Tanpa tenggat',
      null => '-',
    };
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Terkumpul',
                value: formatRupiah(goal.saved),
                highlight: true,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _StatTile(
                label: 'Sisa',
                value: formatRupiah(goal.remaining),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                key: const Key('catch-up'),
                label: 'Kejar deadline',
                value: catchUp,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _StatTile(
                label: 'Target',
                value: formatRupiah(goal.target),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.putih,
          border: Border.all(
            color: highlight ? c.mintBorder : c.tileBorder,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(VillageRadius.tile),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: villageText(fontSize: 10, color: c.redup),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: villageText(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: highlight ? c.mintText : c.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "SETORAN TERAKHIR" with the total number of deposits.
class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Semantics(
      container: true,
      header: true,
      label: 'Setoran terakhir, $count setoran',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'SETORAN TERAKHIR',
                style: villageText(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: c.redup,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: c.putih,
                borderRadius: BorderRadius.circular(VillageRadius.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                child: Text(
                  '$count',
                  style: villageText(fontSize: 11, color: c.redup),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContributionRow extends StatelessWidget {
  const _ContributionRow({required this.contribution});

  final Contribution contribution;

  static const double _dateWidth = 76;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final note = contribution.note?.trim();
    final label = note == null || note.isEmpty ? 'Setoran' : note;
    final date = formatShortDate(contribution.date.toLocal());
    final amount = '+${formatRupiah(contribution.amount)}';
    return Semantics(
      container: true,
      label: '$date, $label, $amount',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.putih,
          border: Border.all(color: c.mintBorder, width: 2),
          borderRadius: BorderRadius.circular(VillageRadius.tile),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          // The amount is the row's key fact: it takes the room it needs,
          // capped at what is left after the date, and scales down (never
          // clips) when even that is too narrow, e.g. at text scale 2.0 on a
          // 320 px screen. The note gets whatever remains.
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                SizedBox(
                  width: _dateWidth,
                  child: Text(
                    date,
                    style: villageText(fontSize: 11, color: c.redup),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: villageText(fontSize: 13, color: c.ink),
                  ),
                ),
                const SizedBox(width: _gap),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(
                      0,
                      constraints.maxWidth - _dateWidth - 6 - _gap,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      amount,
                      maxLines: 1,
                      style: villageText(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: c.mintText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return VillageCard(
      key: const Key('empty-history'),
      padding: const EdgeInsets.all(14),
      child: Text(
        'Belum ada setoran. Setoran pertama memasang fondasi kavling ini.',
        style: villageText(fontSize: 13, color: c.redup, height: 1.4),
      ),
    );
  }
}

/// Load failure. A missing goal (404, or a goal of another user) cannot be
/// retried, so it offers the way back to the Desa; other failures retry.
/// 401 never lands here: the router already moved to `/login` (T5).
class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, this.onRetry});

  final Object error;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final notFound = error is NotFoundException;
    final title = switch (error) {
      NotFoundException() => 'Kavling tidak ditemukan',
      NetworkException() => 'Desa sedang offline',
      ServerException() => 'Balai Desa sedang tutup',
      ForbiddenException() => 'Kavling ini terkunci',
      _ => 'Kavling belum bisa dimuat',
    };
    final message = switch (error) {
      NotFoundException() => 'Kavling ini sudah tidak ada atau bukan milikmu.',
      AppException(:final message) => message,
      _ => 'Ada yang tidak beres. Coba lagi.',
    };
    final retry = onRetry;
    return VillageCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: villageText(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(message, style: villageText(fontSize: 13, color: c.redup)),
          const SizedBox(height: 16),
          if (notFound || retry == null)
            VillageButton(
              label: 'Kembali ke desa',
              onPressed: () => context.go('/'),
            )
          else
            VillageButton(label: 'Coba lagi', onPressed: retry),
        ],
      ),
    );
  }
}
