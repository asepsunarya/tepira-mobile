import 'package:flutter/services.dart';

/// [digits] grouped by thousands with `.`, keeping a leading `-`:
/// `1500000` -> `1.500.000`, `-25000` -> `-25.000`.
String groupRupiahDigits(String digits) {
  final negative = digits.startsWith('-');
  final plain = negative ? digits.substring(1) : digits;
  final grouped = StringBuffer(negative ? '-' : '');
  for (var i = 0; i < plain.length; i++) {
    if (i > 0 && (plain.length - i) % 3 == 0) grouped.write('.');
    grouped.write(plain[i]);
  }
  return grouped.toString();
}

/// Keeps a leading `-` and the digits, grouped by thousands with `.`. An
/// asset may be overdrawn and an old debt wallet may be stored negative, so
/// the sign must survive; whether it is allowed is the validator's call.
///
/// Amounts are read the Indonesian way: `.` groups thousands and `,` starts a
/// fraction, which is dropped because rupiah are whole. A pasted
/// `1.500.000,50` (or `Rp1.500.000,-`) becomes `1.500.000`; the decimal part
/// never joins the digits and inflates the amount. A single `,` typed into
/// the field is ignored instead, so it cannot wipe the digits after it.
///
/// The cursor stays after the same digit it followed before regrouping, and
/// a backspace onto a `.` separator deletes the digit before it.
class SignedRupiahFormatter extends TextInputFormatter {
  const SignedRupiahFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    final end = newValue.selection.end;
    var cursor = end < 0 || end > text.length ? text.length : end;

    if (_removedOnly(oldValue.text, text, cursor, '.') &&
        cursor > 0 &&
        _isDigit(text[cursor - 1])) {
      // Backspace onto a separator: delete the digit it grouped instead.
      text = text.substring(0, cursor - 1) + text.substring(cursor);
      cursor -= 1;
    } else if (cursor > 0 &&
        text[cursor - 1] == ',' &&
        _removedOnly(text, oldValue.text, cursor - 1, ',')) {
      // A typed comma: drop it rather than cut the digits after it.
      text = oldValue.text;
      cursor -= 1;
    }

    // Keep a leading '-' and the digits of the whole part, remembering where
    // each kept character sat in [text].
    final start = text.length - text.trimLeft().length;
    final trimmed = text.trim();
    final comma = trimmed.indexOf(',');
    final wholeEnd = start + (comma < 0 ? trimmed.length : comma);
    final kept = <int>[];
    final chars = StringBuffer();
    final negative = trimmed.startsWith('-');
    if (negative) {
      kept.add(start);
      chars.write('-');
    }
    for (var i = start; i < wholeEnd; i++) {
      if (_isDigit(text[i])) {
        kept.add(i);
        chars.write(text[i]);
      }
    }

    // Drop leading zeros that are followed by another digit.
    var signed = chars.toString();
    final first = negative ? 1 : 0;
    var zeros = 0;
    while (first + zeros + 1 < signed.length && signed[first + zeros] == '0') {
      zeros++;
    }
    if (zeros > 0) {
      signed = signed.substring(0, first) + signed.substring(first + zeros);
      kept.removeRange(first, first + zeros);
    }

    final formatted = groupRupiahDigits(signed);
    final before = kept.where((i) => i < cursor).length;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: _offsetAfter(formatted, before),
      ),
    );
  }

  /// Whether [shorter] is [longer] with the single [char] at [at] removed.
  static bool _removedOnly(
    String longer,
    String shorter,
    int at,
    String char,
  ) =>
      longer.length == shorter.length + 1 &&
      at >= 0 &&
      at < longer.length &&
      longer[at] == char &&
      longer.substring(0, at) + longer.substring(at + 1) == shorter;

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  /// The offset in [formatted] just after its first [count] digits (or `-`).
  static int _offsetAfter(String formatted, int count) {
    if (count <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (formatted[i] != '.') seen++;
      if (seen == count) return i + 1;
    }
    return formatted.length;
  }
}
