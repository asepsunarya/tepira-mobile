import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../model/build_stage.dart';

/// 44px tile with a small drawing of a goal's [stage], from Main.dc.html.
class BuildStageIcon extends StatelessWidget {
  const BuildStageIcon({super.key, required this.stage});

  final BuildStage stage;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: stageSoftColor(c, stage),
          borderRadius: BorderRadius.circular(VillageRadius.tile),
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: const Size.square(26),
          painter: _StagePainter(stage, c),
        ),
      ),
    );
  }
}

/// Indonesian name of a [BuildStage], shown on badges.
String stageLabel(BuildStage stage) => switch (stage) {
      BuildStage.lahan => 'Lahan',
      BuildStage.fondasi => 'Fondasi',
      BuildStage.dinding => 'Dinding',
      BuildStage.atap => 'Atap',
      BuildStage.selesai => 'Selesai',
    };

/// Soft background of a stage's tile and badge.
Color stageSoftColor(VillageColors c, BuildStage stage) => switch (stage) {
      BuildStage.lahan => c.track,
      BuildStage.fondasi => c.kuningSoft,
      BuildStage.dinding => c.mintSoft,
      BuildStage.atap => c.pinkSoft,
      BuildStage.selesai => c.mintSoft,
    };

/// Strong color of a stage: badge text and progress bar.
Color stageStrongColor(VillageColors c, BuildStage stage) => switch (stage) {
      BuildStage.lahan => c.redup,
      BuildStage.fondasi => c.kuningText,
      BuildStage.dinding => c.mintText,
      BuildStage.atap => c.pinkText,
      BuildStage.selesai => c.mintText,
    };

/// Draws on a 24x24 grid scaled to the canvas, like the design's SVGs.
class _StagePainter extends CustomPainter {
  const _StagePainter(this.stage, this.c);

  final BuildStage stage;
  final VillageColors c;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final outline = Paint()
      ..color = c.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    void box(Rect rect, Color fill, {bool stroke = true}) {
      canvas.drawRect(rect, Paint()..color = fill);
      if (stroke) canvas.drawRect(rect, outline);
    }

    void roof() {
      canvas.drawPath(
        Path()
          ..moveTo(3, 11)
          ..lineTo(12, 3)
          ..lineTo(21, 11)
          ..close(),
        Paint()..color = c.pink,
      );
    }

    switch (stage) {
      case BuildStage.lahan:
        canvas.drawLine(
          const Offset(3, 20),
          const Offset(21, 20),
          outline..strokeCap = StrokeCap.round,
        );
        for (final x in [6.0, 18.0]) {
          box(Rect.fromLTWH(x - 1, 13, 2, 7), c.koinTua, stroke: false);
        }
      case BuildStage.fondasi:
        box(const Rect.fromLTWH(4, 16, 16, 4), c.disabled);
      case BuildStage.dinding:
        box(const Rect.fromLTWH(5, 10, 14, 10), c.kartu);
        box(const Rect.fromLTWH(10, 14, 4, 6), c.koin, stroke: false);
      case BuildStage.atap:
        roof();
        box(const Rect.fromLTWH(5, 11, 14, 9), c.kartu);
        box(const Rect.fromLTWH(10, 14, 4, 6), c.ink, stroke: false);
      case BuildStage.selesai:
        roof();
        box(const Rect.fromLTWH(5, 11, 14, 9), c.kartu);
        box(const Rect.fromLTWH(10, 14, 4, 6), c.ink, stroke: false);
        box(const Rect.fromLTWH(15, 13, 3, 3), c.koin, stroke: false);
        box(const Rect.fromLTWH(6, 13, 3, 3), c.koin, stroke: false);
    }
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.stage != stage || old.c != c;
}
