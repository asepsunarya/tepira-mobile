import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../model/build_stage.dart';
import '../model/display_percent.dart';
import '../model/goal.dart';
import 'build_stage_icon.dart';

/// One plot ("kavling") on the Desa list: stage icon, title, stage badge,
/// "Rp… dari Rp… · N%" and a thin progress bar colored by stage.
class GoalRow extends StatelessWidget {
  const GoalRow({super.key, required this.goal, this.onTap});

  final Goal goal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final stage = buildStage(saved: goal.saved, target: goal.target);
    final percent = displayPercent(saved: goal.saved, target: goal.target);
    final amounts =
        '${formatRupiah(goal.saved)} dari ${formatRupiah(goal.target)}';
    final radius = BorderRadius.circular(16);

    return Semantics(
      button: onTap != null,
      label: '${goal.title}, tahap ${stageLabel(stage)}, $amounts, $percent%',
      excludeSemantics: true,
      child: Material(
        color: c.putih,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: c.tileBorder, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                BuildStageIcon(stage: stage),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              goal.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: villageText(fontSize: 14, color: c.ink),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StageBadge(stage: stage),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$amounts · $percent%',
                        style: villageText(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.redup,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(VillageRadius.pill),
                        child: LinearProgressIndicator(
                          value: percent / 100,
                          minHeight: 6,
                          color: _barColor(c, stage),
                          backgroundColor: c.track,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _barColor(VillageColors c, BuildStage stage) => switch (stage) {
        BuildStage.lahan || BuildStage.fondasi => c.koin,
        BuildStage.dinding || BuildStage.selesai => c.mint,
        BuildStage.atap => c.pink,
      };
}

class _StageBadge extends StatelessWidget {
  const _StageBadge({required this.stage});

  final BuildStage stage;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: stageSoftColor(c, stage),
        borderRadius: BorderRadius.circular(VillageRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          stageLabel(stage),
          style: villageText(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: stageStrongColor(c, stage),
          ),
        ),
      ),
    );
  }
}
