import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/village_card.dart';

/// Loading placeholder of the Desa screen (artboard SkeletonDesa): a HUD
/// card, the caption "Si penabung sedang berjalan ke desa…" and three plot
/// rows of soft bars. The bars pulse unless the platform asks for reduced
/// motion; the caption stays still, as in the artboard.
class DesaSkeleton extends StatefulWidget {
  const DesaSkeleton({super.key});

  @override
  State<DesaSkeleton> createState() => _DesaSkeletonState();
}

class _DesaSkeletonState extends State<DesaSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    lowerBound: 0.55,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memuat desa',
      container: true,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            FadeTransition(
              opacity: _pulse,
              child: const VillageCard(
                child: Row(
                  children: [
                    _Bar(width: 36, height: 36),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Bar(width: 90, height: 12),
                          SizedBox(height: 6),
                          _Bar(width: 150, height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(child: _Caption()),
            const SizedBox(height: 12),
            FadeTransition(
              opacity: _pulse,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _Bar(width: 100, height: 12),
                  ),
                  for (var i = 0; i < 3; i++) ...[
                    const SizedBox(height: 8),
                    const _RowSkeleton(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "walking to the village" pill from the artboard's island panel,
/// shown on its own since the island itself is out of scope.
class _Caption extends StatelessWidget {
  const _Caption();

  static const String text = 'Si penabung sedang berjalan ke desa…';

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.kartu.withValues(alpha: 0.92),
        border: Border.all(color: c.putih, width: 2),
        borderRadius: BorderRadius.circular(VillageRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              value: 0.75,
              strokeWidth: 3,
              strokeCap: StrokeCap.round,
              color: c.pink,
              backgroundColor: Colors.transparent,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: villageText(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: c.redup,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.putih,
        border: Border.all(color: c.tileBorder, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          _Bar(width: 44, height: 44, radius: VillageRadius.tile),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Bar(width: 120, height: 12),
                SizedBox(height: 6),
                _Bar(width: 180, height: 10),
                SizedBox(height: 6),
                _Bar(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({this.width, required this.height, this.radius});

  final double? width;
  final double height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: VillageColors.of(context).garis,
        borderRadius: BorderRadius.circular(radius ?? VillageRadius.pill),
      ),
    );
  }
}
