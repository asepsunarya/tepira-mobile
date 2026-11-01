import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme.dart';
import '../model/build_stage.dart';
import 'build_stage_icon.dart';

/// The plot drawing on the Kavling screen: the building at [stage] on a
/// small island under the sky, with a "Tahap …" badge. Drawings come from
/// the "Tahap bangunan dari progres" row of Ilustrasi.dc.html.
class StageIllustration extends StatelessWidget {
  const StageIllustration({super.key, required this.stage});

  final BuildStage stage;

  @override
  Widget build(BuildContext context) {
    final c = VillageColors.of(context);
    final label = 'Tahap ${stageLabel(stage).toLowerCase()}';
    return Semantics(
      container: true,
      label: label,
      image: true,
      excludeSemantics: true,
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFD8EFFA), Color(0xFFBFE3F3)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              top: 12,
              child: SvgPicture.string(
                key: ValueKey('stage-${stage.name}'),
                stageSvg(stage),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.kartu.withValues(alpha: 0.92),
                  border: Border.all(color: c.putih, width: 2),
                  borderRadius: BorderRadius.circular(VillageRadius.pill),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(
                    label,
                    style: villageText(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: stageStrongColor(c, stage),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SVG markup (120x90) of the building at [stage], from Ilustrasi.dc.html.
String stageSvg(BuildStage stage) {
  final building = switch (stage) {
    BuildStage.lahan => _lahan,
    BuildStage.fondasi => _fondasi,
    BuildStage.dinding => _dinding,
    BuildStage.atap => _atap,
    BuildStage.selesai => _selesai,
  };
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 90">'
      '<ellipse cx="60" cy="78" rx="54" ry="10" fill="#6cc8ad"/>'
      '$building</svg>';
}

const String _lahan =
    '<path d="M30 74 L90 74 L90 50 L30 50 Z" fill="none" stroke="#5a4a5e" '
    'stroke-width="2" stroke-dasharray="5 4"/>'
    '<rect x="28" y="46" width="4" height="30" fill="#8b6b4a"/>'
    '<rect x="88" y="46" width="4" height="30" fill="#8b6b4a"/>';

const String _fondasi =
    '<rect x="28" y="66" width="64" height="8" rx="1" fill="#cdbfc9"/>';

const String _dinding =
    '<rect x="28" y="68" width="64" height="6" rx="1" fill="#cdbfc9"/>'
    '<rect x="32" y="34" width="56" height="36" fill="#fffaf7" '
    'stroke="#e8dce4" stroke-width="2"/>'
    '<path d="M32 34 L88 34" stroke="#ff7eb3" stroke-width="3" '
    'stroke-dasharray="6 5"/>'
    '<rect x="52" y="50" width="14" height="20" fill="#f3c35b"/>';

const String _atap =
    '<rect x="32" y="38" width="56" height="34" fill="#fffaf7"/>'
    '<path d="M28 40 L60 14 L92 40 Z" fill="#ff7eb3"/>'
    '<rect x="52" y="52" width="14" height="20" fill="#5a4a5e"/>'
    '<rect x="72" y="46" width="8" height="8" fill="#cfe9f7"/>';

const String _selesai =
    '<rect x="32" y="38" width="56" height="34" fill="#fffaf7"/>'
    '<path d="M28 40 L60 14 L92 40 Z" fill="#ff7eb3"/>'
    '<rect x="74" y="18" width="8" height="14" fill="#cdbfc9"/>'
    '<rect x="59" y="2" width="2" height="16" fill="#5a4a5e"/>'
    '<path d="M61 3 L74 7 L61 11 Z" fill="#6cc8ad"/>'
    '<rect x="52" y="52" width="14" height="20" fill="#5a4a5e"/>'
    '<rect x="38" y="46" width="8" height="8" fill="#f3c35b"/>'
    '<rect x="72" y="46" width="8" height="8" fill="#f3c35b"/>';
