/// Strict readers for the mobile API's JSON (SPEC v1 §3, SPEC-v2 §3).
///
/// The contract says nullable fields are always present, so a missing key or
/// a wrong type throws [FormatException]; repositories turn that into a
/// "Jawaban server tidak dikenali." error instead of showing wrong data.
library;

import '../core/wib.dart';

T requiredField<T extends Object>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('"$key" must be a $T', value);
}

T? nullableField<T extends Object>(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('"$key" is missing (nullable, never missing)');
  }
  final value = json[key];
  if (value == null || value is T) return value as T?;
  throw FormatException('"$key" must be a $T or null', value);
}

/// The JSON object at [key].
Map<String, Object?> objectField(Map<String, Object?> json, String key) =>
    jsonObject(json[key], key);

/// [value] as a JSON object; [what] names it in the error.
Map<String, Object?> jsonObject(Object? value, [String what = 'value']) {
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('"$what" must be a JSON object', value);
}

/// The list at [key], each item parsed with [parse] as a JSON object.
List<T> listField<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?> item) parse,
) {
  final items = requiredField<List<Object?>>(json, key);
  return [for (final item in items) parse(jsonObject(item, '$key[]'))];
}

final _isoInstant = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$');

/// ISO-8601 UTC timestamp at [key], e.g. `2026-11-01T07:00:00.000Z`.
DateTime instantField(Map<String, Object?> json, String key) {
  final value = requiredField<String>(json, key);
  if (!_isoInstant.hasMatch(value)) {
    throw FormatException('"$key" must be an ISO-8601 UTC timestamp', value);
  }
  return DateTime.parse(value);
}

/// `period` `{year, month}` at [key] as a [WibMonth].
WibMonth periodField(Map<String, Object?> json, String key) {
  final period = objectField(json, key);
  final year = requiredField<int>(period, 'year');
  final month = requiredField<int>(period, 'month');
  if (month < 1 || month > 12) {
    throw FormatException('"$key.month" must be 1..12', month);
  }
  return WibMonth(year, month);
}
