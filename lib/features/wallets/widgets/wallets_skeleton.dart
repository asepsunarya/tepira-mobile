import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/village_card.dart';

/// Loading placeholder of the Dompet screen (style of artboard
/// SkeletonDaftar): the totals card and three wallet rows as soft bars. It
/// holds still, so it never keeps a frame scheduled.
class WalletsSkeleton extends StatelessWidget {
  const WalletsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Memuat dompet',
      container: true,
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            const VillageCard(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bar(width: 80, height: 10),
                  SizedBox(height: 8),
                  _Bar(width: 170, height: 26),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _Bar(height: 44)),
                      SizedBox(width: 8),
                      Expanded(child: _Bar(height: 44)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < 3; i++) ...[
              const VillageCard(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    _Bar(width: 44, height: 44),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Bar(width: 110, height: 12),
                          SizedBox(height: 6),
                          _Bar(width: 160, height: 10),
                        ],
                      ),
                    ),
                    _Bar(width: 70, height: 14),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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
