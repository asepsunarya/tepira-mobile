/// Building stage of a goal's plot, from empty land to a finished house.
enum BuildStage { lahan, fondasi, dinding, atap, selesai }

/// The stage for [saved] out of [target] rupiah: `lahan` at 0, `fondasi`
/// above 0, `dinding` from 30%, `atap` from 70%, `selesai` from 100%.
///
/// Compares in integers so the 30% and 70% boundaries are exact.
BuildStage buildStage({required int saved, required int target}) {
  if (saved <= 0 || target <= 0) return BuildStage.lahan;
  if (saved >= target) return BuildStage.selesai;
  if (saved * 10 >= target * 7) return BuildStage.atap;
  if (saved * 10 >= target * 3) return BuildStage.dinding;
  return BuildStage.fondasi;
}
