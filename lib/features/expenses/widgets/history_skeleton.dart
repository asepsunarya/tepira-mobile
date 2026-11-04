import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Loading placeholder of the Riwayat list (artboard SkeletonDaftar): the
/// total tile, then two day titles with their rows, as soft bars. It holds
/// still, so it never keeps a frame scheduled.
class HistorySkeleton extends StatelessWidget {
  const HistorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memuat riwayat',
      container: true,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            const _Bar(height: 52),
            for (final rows in const [2, 3]) ...[
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: _Bar(width: 90, height: 10),
              ),
              for (var i = 0; i < rows; i++) ...[
                const SizedBox(height: 6),
                const _Bar(height: 48),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({this.width, required this.height});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.track,
        borderRadius: BorderRadius.circular(VillageRadius.note),
      ),
    );
  }
}
