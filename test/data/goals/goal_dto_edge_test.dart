import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/data/goals/goal_dto.dart';

/// Edge cases for goal parsing beyond the fixtures, checked against the
/// backend's `lib/mobile/goals.ts` (`toMobileGoal`, `toMobileGoalDetail`) and
/// `goalPlan` in `lib/cyrene/core.ts` on tepira main.
Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, Object?>;

/// Fixture goal 12, with every nullable field set.
Map<String, Object?> _item() => Map.of(
      (_fixture('mobile_goals.json')['goals']! as List)[1]
          as Map<String, Object?>,
    );

Map<String, Object?> _detail() => Map.of(
      _fixture('mobile_goal_detail.json')['goal']! as Map<String, Object?>,
    );

/// Round-trips through JSON text, like the response a client really decodes.
Map<String, Object?> _wire(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('percent', () {
    test('above 100 is kept as sent (the client never clamps or recomputes)',
        () {
      final goal = goalFromJson(_wire(_item()..['percent'] = 150));
      expect(goal.percent, 150.0);
    });

    test('fractional values keep their decimal', () {
      for (final value in [0.1, 33.3, 99.9, 41.3]) {
        expect(
          goalFromJson(_wire(_item()..['percent'] = value)).percent,
          value,
        );
      }
    });

    test('an int percent becomes a double', () {
      final goal = goalFromJson(_wire(_item()..['percent'] = 100));
      expect(goal.percent, isA<double>());
      expect(goal.percent, 100.0);
    });

    test('a percent sent as a string is a format error', () {
      expect(
        () => goalFromJson(_wire(_item()..['percent'] = '41.3')),
        throwsFormatException,
      );
    });
  });

  group('money and counters', () {
    test('negative remaining is passed through unchanged', () {
      final goal = goalFromJson(_wire(_item()..['remaining'] = -500));
      expect(goal.remaining, -500);
    });

    test('the largest contract target parses', () {
      final goal = goalFromJson(
        _wire(
          _item()
            ..['target'] = 2147483647
            ..['saved'] = 2147483647
            ..['remaining'] = 0,
        ),
      );
      expect(goal.target, 2147483647);
      expect(goal.saved, 2147483647);
    });

    test('saved above target parses (several deposits overshoot)', () {
      final goal = goalFromJson(
        _wire(
          _item()
            ..['saved'] = 16000000
            ..['percent'] = 100
            ..['remaining'] = 0
            ..['perMonthNeeded'] = null,
        ),
      );
      expect(goal.saved, 16000000);
      expect(goal.perMonthNeeded, isNull);
    });

    test('an id sent as a string is a format error', () {
      expect(
        () => goalFromJson(_wire(_item()..['id'] = '12')),
        throwsFormatException,
      );
    });
  });

  group('deadline', () {
    test('null deadline with null daysLeft and perMonthNeeded', () {
      final goal = goalFromJson(
        _wire(
          _item()
            ..['deadline'] = null
            ..['daysLeft'] = null
            ..['perMonthNeeded'] = null,
        ),
      );
      expect(goal.deadline, isNull);
      expect(goal.daysLeft, isNull);
      expect(goal.perMonthNeeded, isNull);
    });

    test('deadline is UTC midnight of the calendar date', () {
      final goal = goalFromJson(_wire(_item()));
      expect(goal.deadline, DateTime.utc(2027, 4, 30));
      expect(goal.deadline!.isUtc, isTrue);
    });

    test('29 February only in a leap year', () {
      expect(
        goalFromJson(_wire(_item()..['deadline'] = '2028-02-29')).deadline,
        DateTime.utc(2028, 2, 29),
      );
      expect(
        () => goalFromJson(_wire(_item()..['deadline'] = '2027-02-29')),
        throwsFormatException,
      );
    });

    test('a timestamp in the deadline field is a format error', () {
      expect(
        () => goalFromJson(
          _wire(_item()..['deadline'] = '2027-04-30T00:00:00.000Z'),
        ),
        throwsFormatException,
      );
    });

    test('daysLeft 0 for a passed deadline parses', () {
      expect(goalFromJson(_wire(_item()..['daysLeft'] = 0)).daysLeft, 0);
    });
  });

  group('timestamps', () {
    test('createdAt is UTC and keeps milliseconds', () {
      final goal = goalFromJson(_wire(_item()));
      expect(goal.createdAt, DateTime.utc(2026, 6, 1, 3, 15));
      expect(goal.createdAt.isUtc, isTrue);
    });

    test('createdAt with a +07:00 offset is a format error', () {
      expect(
        () => goalFromJson(
          _wire(_item()..['createdAt'] = '2026-06-01T10:15:00.000+07:00'),
        ),
        throwsFormatException,
      );
    });

    test('lastContribution.date is UTC', () {
      final goal = goalFromJson(_wire(_item()));
      expect(goal.lastContribution!.date, DateTime.utc(2026, 10, 28, 12, 45));
      expect(goal.lastContribution!.date.isUtc, isTrue);
    });
  });

  group('optional (nullable) fields', () {
    test('all nullable goal fields null at once', () {
      final goal = goalFromJson(
        _wire(
          _item()
            ..['description'] = null
            ..['deadline'] = null
            ..['daysLeft'] = null
            ..['perMonthNeeded'] = null
            ..['lastContribution'] = null,
        ),
      );
      expect(goal.description, isNull);
      expect(goal.deadline, isNull);
      expect(goal.daysLeft, isNull);
      expect(goal.perMonthNeeded, isNull);
      expect(goal.lastContribution, isNull);
    });

    test(
        'all nullable goal fields missing is a format error (contract: '
        'nullable, never missing)', () {
      final json = _wire(_item())
        ..remove('description')
        ..remove('deadline')
        ..remove('daysLeft')
        ..remove('perMonthNeeded')
        ..remove('lastContribution');
      expect(() => goalFromJson(json), throwsFormatException);
    });

    test('lastContribution that is not an object is a format error', () {
      expect(
        () => goalFromJson(_wire(_item()..['lastContribution'] = '2026-10-28')),
        throwsFormatException,
      );
      expect(
        () => goalFromJson(_wire(_item()..['lastContribution'] = <Object?>[])),
        throwsFormatException,
      );
    });

    test('empty description is kept as an empty string', () {
      expect(
        goalFromJson(_wire(_item()..['description'] = '')).description,
        '',
      );
    });
  });

  group('contributions', () {
    test('note null parses to null', () {
      final c = contributionFromJson(
        _wire({
          'id': 1,
          'amount': 10000,
          'note': null,
          'date': '2026-10-28T12:45:00.000Z',
        }),
      );
      expect(c.note, isNull);
    });

    test('note with emoji and a newline is kept verbatim', () {
      final c = contributionFromJson(
        _wire({
          'id': 1,
          'amount': 10000,
          'note': 'Gaji 🎉\nbulan ini',
          'date': '2026-10-28T12:45:00.000Z',
        }),
      );
      expect(c.note, 'Gaji 🎉\nbulan ini');
    });

    test('a non-object entry in contributions is a format error', () {
      expect(
        () => goalDetailFromJson(_wire(_detail()..['contributions'] = [1])),
        throwsFormatException,
      );
    });

    test('contributions that is null is a format error', () {
      expect(
        () => goalDetailFromJson(_wire(_detail()..['contributions'] = null)),
        throwsFormatException,
      );
    });

    test('fewer listed contributions than contributionCount (200 cap) parses',
        () {
      final json = _wire(_detail()..['contributionCount'] = 250);
      final detail = goalDetailFromJson(json);
      expect(detail.goal.contributionCount, 250);
      expect(detail.contributions, hasLength(4));
    });

    test('order is kept as the server sent it', () {
      final detail = goalDetailFromJson(_wire(_detail()));
      expect(detail.contributions.map((c) => c.id), [142, 130, 117, 101]);
    });
  });

  group('unknown extra fields are ignored', () {
    test('on a goal, lastContribution and contribution', () {
      final base = goalDetailFromJson(_wire(_detail()));
      final json = _wire(_detail());
      json['futureField'] = {'nested': true};
      json['stage'] = 'atap';
      (json['lastContribution']! as Map)['wallet'] = 'BCA';
      for (final c in json['contributions']! as List) {
        (c as Map)['source'] = 'gaji';
      }
      expect(goalDetailFromJson(json), base);
    });

    test('on a list item', () {
      final base = goalFromJson(_wire(_item()));
      expect(goalFromJson(_wire(_item()..['userId'] = 'user_owner')), base);
    });
  });

  group('value equality', () {
    test('two parses of the same JSON are equal with equal hash codes', () {
      final a = goalDetailFromJson(_wire(_detail()));
      final b = goalDetailFromJson(_wire(_detail()));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different contribution note makes details unequal', () {
      final a = goalDetailFromJson(_wire(_detail()));
      final json = _wire(_detail());
      ((json['contributions']! as List).first as Map)['note'] = 'lain';
      expect(goalDetailFromJson(json), isNot(a));
    });
  });
}
