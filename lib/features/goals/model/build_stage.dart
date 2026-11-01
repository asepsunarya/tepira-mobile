import 'display_percent.dart';

/// Building stage of a goal's plot, from empty land to a finished house.
enum BuildStage { lahan, fondasi, dinding, atap, selesai }

/// The stage for [saved] out of [target] rupiah: `lahan` at 0, `fondasi`
/// above 0, `dinding` from 30%, `atap` from 70%, `selesai` from 100%.
///
/// Uses [displayPercent], so the stage always agrees with the percent the
/// user sees and `selesai` needs `saved >= target`.
BuildStage buildStage({required int saved, required int target}) {
  if (saved <= 0 || target <= 0) return BuildStage.lahan;
  final percent = displayPercent(saved: saved, target: target);
  if (percent >= 100) return BuildStage.selesai;
  if (percent >= 70) return BuildStage.atap;
  if (percent >= 30) return BuildStage.dinding;
  return BuildStage.fondasi;
}
