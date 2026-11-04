import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../core/widgets/village_button.dart';
import '../../core/widgets/village_card.dart';
import 'goal_providers.dart';
import 'model/goal.dart';
import 'widgets/desa_skeleton.dart';
import 'widgets/goal_row.dart';

/// The Desa screen (`/`, artboard Main): a small HUD, the list of plots and
/// a dock with the Desa tab and the Catat button. Pull down to reload.
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

    final Widget body;
    if (list != null && !goals.hasError) {
      body = _Refreshable(
        onRefresh: notifier.refresh,
        children: [
          _Hud(userName: userName, goals: list),
          const SizedBox(height: 12),
          if (list.isEmpty)
            _EmptyVillage(onReload: notifier.refresh)
          else
            ..._plotList(context, list),
        ],
      );
    } else if (goals.hasError && !goals.isLoading) {
      body = _Refreshable(
        onRefresh: notifier.refresh,
        children: [_LoadError(error: goals.error!, onRetry: notifier.refresh)],
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
          child: Column(
            children: [
              Expanded(child: body),
              const _Dock(),
            ],
          ),
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

/// Bottom dock: only the active Desa tab and the Catat button, which opens
/// the Jajan tab so a quick expense takes three taps (SPEC-v2 §4).
class _Dock extends StatelessWidget {
  const _Dock();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.kartu.withValues(alpha: 0.88),
          border: Border.all(color: c.putih, width: 2),
          borderRadius: BorderRadius.circular(VillageRadius.card),
          boxShadow: [
            BoxShadow(
              color: c.shadow,
              offset: const Offset(0, 10),
              blurRadius: 30,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DockTile(
                icon: Icons.cottage_rounded,
                label: 'Desa',
                selected: true,
              ),
              const SizedBox(width: 6),
              _DockTile(
                key: const Key('record'),
                icon: Icons.edit_note_rounded,
                label: 'Catat',
                onTap: () => context.push(ExpenseRoutes.record),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockTile extends StatelessWidget {
  const _DockTile({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final foreground = selected ? c.pinkText : c.redup;
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? c.pinkSoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: selected
              ? BorderSide(color: c.pink.withValues(alpha: 0.4), width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox.square(
            dimension: 62,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: foreground),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: villageText(fontSize: 10, color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
