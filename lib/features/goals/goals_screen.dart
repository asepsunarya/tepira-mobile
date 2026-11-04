import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import '../today/today_providers.dart';
import '../today/widgets/safe_today_card.dart';
import 'goal_providers.dart';
import 'model/goal.dart';
import 'widgets/desa_skeleton.dart';
import 'widgets/goal_row.dart';

/// The Desa screen (`/`, artboard Main): a small HUD, the "Aman dipakai hari
/// ini" card with this month's tiles and the list of plots. The app dock
/// sits below it (`lib/features/shell/app_dock.dart`). Pull down to reload
/// both.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key, this.userName});

  /// Signed-in user's name for the HUD; falls back to a generic greeting.
  final String? userName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = VillageColors.of(context);
    final goals = ref.watch(goalsProvider);
    final notifier = ref.read(goalsProvider.notifier);
    final list = goals.valueOrNull;
    Future<void> refresh() => Future.wait([
          notifier.refresh(),
          ref.read(todayProvider.notifier).refresh(),
        ]);

    final Widget body;
    if (list != null && !goals.hasError) {
      body = _Refreshable(
        onRefresh: refresh,
        children: [
          _Hud(userName: userName, goals: list),
          const SizedBox(height: 12),
          const TodaySection(),
          const SizedBox(height: 12),
          if (list.isEmpty)
            _EmptyVillage(onReload: notifier.refresh)
          else
            ..._plotList(context, list),
        ],
      );
    } else if (goals.hasError && !goals.isLoading) {
      body = _Refreshable(
        onRefresh: refresh,
        children: [
          const TodaySection(),
          const SizedBox(height: 12),
          _LoadError(error: goals.error!, onRetry: notifier.refresh),
        ],
      );
    } else {
      body = const DesaSkeleton();
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
          child: body,
        ),
      ),
    );
  }

  List<Widget> _plotList(BuildContext context, List<Goal> goals) {
    final c = VillageColors.of(context);
    return [
      Row(
        children: [
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'KAVLING GOAL',
              style: villageText(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: c.redup,
                letterSpacing: 0.5,
              ),
            ),
          ),
          TextButton.icon(
            key: const Key('build-plot'),
            onPressed: () => context.push(GoalRoutes.create),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Bangun kavling'),
            style: TextButton.styleFrom(
              foregroundColor: c.pinkText,
              minimumSize: const Size(44, 44),
              textStyle: villageText(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      for (final goal in goals) ...[
        GoalRow(
          goal: goal,
          onTap: () => context.push(GoalRoutes.detail(goal.id)),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }
}

/// Pull-to-refresh list that scrolls even when its content is short.
class _Refreshable extends StatelessWidget {
  const _Refreshable({required this.onRefresh, required this.children});

  final Future<void> Function() onRefresh;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: children,
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.userName, required this.goals});

  final String? userName;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final name = userName?.trim();
    final shownName = name == null || name.isEmpty ? 'Warga desa' : name;
    final building = goals.where((goal) => goal.saved < goal.target).length;
    return VillageCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Semantics(
            container: true,
            button: true,
            label: 'Pengaturan',
            child: InkResponse(
              key: const Key('open-settings'),
              onTap: () => context.push(kSettingsPath),
              radius: 24,
              child: SizedBox.square(
                dimension: 44,
                child: ExcludeSemantics(
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: c.mintSoft,
                    foregroundColor: c.mintText,
                    child: Text(
                      shownName.characters.first.toUpperCase(),
                      style: villageText(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shownName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: villageText(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: c.ink,
                  ),
                ),
                Text(
                  goals.isEmpty
                      ? 'Belum ada kavling'
                      : '$building kavling sedang dibangun',
                  style: villageText(fontSize: 11, color: c.redup),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Short version of artboard DesaKosong.
class _EmptyVillage extends StatelessWidget {
  const _EmptyVillage({required this.onReload});

  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return VillageCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Desamu masih sepi',
            style: villageText(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Belum ada kavling. Patok kavling pertama, '
            'goal tabunganmu jadi lahan berpatok.',
            style: villageText(fontSize: 13, color: c.redup),
          ),
          const SizedBox(height: 16),
          VillageButton(
            key: const Key('build-first-plot'),
            label: 'Bangun kavling',
            onPressed: () => context.push(GoalRoutes.create),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onReload,
            style: TextButton.styleFrom(
              foregroundColor: c.pinkText,
              minimumSize: const Size(44, 44),
              textStyle: villageText(fontSize: 12, fontWeight: FontWeight.w900),
            ),
            child: const Text('Sudah punya data di tepira.id? Muat ulang'),
          ),
        ],
      ),
    );
  }
}

/// Load failure with a retry. 401 never lands here: the router already
/// moved to `/login` (T5).
class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final title = switch (error) {
      NetworkException() => 'Desa sedang offline',
      ServerException() => 'Balai Desa sedang tutup',
      ForbiddenException() => 'Desa ini terkunci',
      _ => 'Desa belum bisa dimuat',
    };
    final message = switch (error) {
      AppException(:final message) => message,
      _ => 'Ada yang tidak beres. Coba lagi.',
    };
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
          VillageButton(label: 'Coba lagi', onPressed: onRetry),
        ],
      ),
    );
  }
}
