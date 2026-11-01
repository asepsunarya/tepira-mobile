/// Client-side checks for the Bangun kavling form. They mirror the server
/// rules of `POST /api/mobile/goals` (SPEC section 3.4), so a form that passes
/// here is only rejected by the server for reasons the client cannot see.
abstract final class NewGoalInput {
  /// Length limits count Unicode code points (`String.runes`), like the
  /// server's `Array.from(s).length`, not UTF-16 units: an emoji counts as 1.
  static const int maxTitleLength = 60;
  static const int maxDescriptionLength = 200;

  /// The largest target the server accepts (the int32 maximum).
  static const int maxTarget = 2147483647;

  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _groupedDigits = RegExp(r'^[0-9]+(\.[0-9]{3})*$');

  /// Error for the goal name, or null when [raw] is valid once trimmed.
  static String? titleError(String raw) {
    final title = raw.trim();
    if (title.isEmpty) return 'Nama goal harus diisi.';
    if (title.runes.length > maxTitleLength) {
      return 'Nama goal maksimal $maxTitleLength karakter.';
    }
    if (title.contains(_controlChars)) {
      return 'Nama goal tidak boleh berisi karakter khusus.';
    }
    return null;
  }

  /// The target in whole rupiah from the field text, which may use `.` as
  /// thousands separator (`1.500.000`). Null for anything else: empty,
  /// negative, decimal or non-numeric text.
  static int? parseTarget(String raw) {
    final text = raw.trim();
    if (!_groupedDigits.hasMatch(text)) return null;
    return int.tryParse(text.replaceAll('.', ''));
  }

  /// Error for the target field text, or null when it is 1..[maxTarget].
  static String? targetError(String raw) {
    if (raw.trim().isEmpty) return 'Target harus diisi.';
    final target = parseTarget(raw);
    if (target == null || target <= 0) {
      return 'Target harus berupa angka bulat lebih dari 0.';
    }
    if (target > maxTarget) return 'Target terlalu besar.';
    return null;
  }

  /// Error for the optional description, or null when it is valid.
  static String? descriptionError(String raw) =>
      raw.trim().runes.length > maxDescriptionLength
          ? 'Deskripsi maksimal $maxDescriptionLength karakter.'
          : null;

  /// The description to send: trimmed, or null when blank.
  static String? description(String raw) {
    final text = raw.trim();
    return text.isEmpty ? null : text;
  }
}
