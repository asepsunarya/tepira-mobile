/// Parses goal JSON from `/api/mobile/goals*` (SPEC section 3.2 to 3.4).
///
/// Strict on purpose: the contract says nullable fields are always present,
/// so a missing key or a wrong type throws [FormatException] and the
/// repository reports an unrecognised answer instead of showing wrong data.
library;

import '../../features/goals/model/goal.dart';

/// Parses one goal item (list, create, and the detail goal without its
/// `contributions`).
Goal goalFromJson(Map<String, Object?> json) {
  final lastContribution = _nullable<Map<Object?, Object?>>(
    json,
    'lastContribution',
  );
  return Goal(
    id: _required<int>(json, 'id'),
    title: _required<String>(json, 'title'),
    description: _nullable<String>(json, 'description'),
    target: _required<int>(json, 'target'),
    saved: _required<int>(json, 'saved'),
    percent: _required<num>(json, 'percent').toDouble(),
    remaining: _required<int>(json, 'remaining'),
    deadline: _calendarDate(_nullable<String>(json, 'deadline')),
    daysLeft: _nullable<int>(json, 'daysLeft'),
    perMonthNeeded: _nullable<int>(json, 'perMonthNeeded'),
    createdAt: _instant(_required<String>(json, 'createdAt')),
    lastContribution: lastContribution == null
        ? null
        : _lastContributionFromJson(lastContribution.cast<String, Object?>()),
    contributionCount: _required<int>(json, 'contributionCount'),
  );
}

/// Parses the `goal` object of `GET /api/mobile/goals/{id}`.
GoalDetail goalDetailFromJson(Map<String, Object?> json) {
  final contributions = _required<List<Object?>>(json, 'contributions');
  return GoalDetail(
    goal: goalFromJson(json),
    contributions: [
      for (final item in contributions)
        if (item is Map)
          contributionFromJson(item.cast<String, Object?>())
        else
          throw const FormatException('contributions[] must be objects'),
    ],
  );
}

/// Parses one entry of a goal's `contributions`.
Contribution contributionFromJson(Map<String, Object?> json) {
  return Contribution(
    id: _required<int>(json, 'id'),
    amount: _required<int>(json, 'amount'),
    note: _nullable<String>(json, 'note'),
    date: _instant(_required<String>(json, 'date')),
  );
}

LastContribution _lastContributionFromJson(Map<String, Object?> json) {
  return LastContribution(
    date: _instant(_required<String>(json, 'date')),
    amount: _required<int>(json, 'amount'),
  );
}

T _required<T extends Object>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('"$key" must be a $T', value);
}

T? _nullable<T extends Object>(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('"$key" is missing (nullable, never missing)');
  }
  final value = json[key];
  if (value == null || value is T) return value as T?;
  throw FormatException('"$key" must be a $T or null', value);
}

final _isoInstant = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$');
final _calendarDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// ISO-8601 UTC timestamp, e.g. `2026-10-28T12:45:00.000Z`.
DateTime _instant(String value) {
  if (!_isoInstant.hasMatch(value)) {
    throw FormatException('expected an ISO-8601 UTC timestamp', value);
  }
  return DateTime.parse(value);
}

/// `YYYY-MM-DD` calendar date as UTC midnight, so it never shifts a day
/// with the device time zone.
DateTime? _calendarDate(String? value) {
  if (value == null) return null;
  final match = _calendarDatePattern.firstMatch(value);
  if (match == null) {
    throw FormatException('expected a YYYY-MM-DD date', value);
  }
  final date = DateTime.utc(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
  if (date.month != int.parse(match[2]!) || date.day != int.parse(match[3]!)) {
    throw FormatException('not a calendar date', value);
  }
  return date;
}
