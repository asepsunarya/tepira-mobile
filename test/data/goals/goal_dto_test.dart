import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tepira_mobile/data/goals/goal_dto.dart';
import 'package:tepira_mobile/features/goals/model/goal.dart';

Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, Object?>;

List<Map<String, Object?>> _listItems() =>
    (_fixture('mobile_goals.json')['goals']! as List)
        .cast<Map<String, Object?>>();

Map<String, Object?> _detailGoal() =>
    _fixture('mobile_goal_detail.json')['goal']! as Map<String, Object?>;

/// The fixture item with every nullable field set, for single-field edits.
Map<String, Object?> _fullItem() => Map.of(_listItems()[1]);

void main() {
  group('mobile_goals.json', () {
    test('parses all four goals in server order', () {
      final goals = _listItems().map(goalFromJson).toList();

      expect(goals.map((g) => g.id), [15, 12, 7, 3]);
    });

    test('parses a goal with every field set', () {
      final goal = goalFromJson(_listItems()[1]);

      expect(
        goal,
        Goal(
          id: 12,
          title: 'Laptop kerja',
          description: 'Ganti laptop lama sebelum proyek baru',
          target: 15000000,
          saved: 6200000,
          percent: 41.3,
          remaining: 8800000,
          deadline: DateTime.utc(2027, 4, 30),
          daysLeft: 180,
          perMonthNeeded: 1466667,
          createdAt: DateTime.utc(2026, 6, 1, 3, 15),
          lastContribution: LastContribution(
            date: DateTime.utc(2026, 10, 28, 12, 45),
            amount: 1200000,
          ),
          contributionCount: 4,
        ),
      );
      expect(goal.createdAt.isUtc, isTrue);
      expect(goal.deadline!.isUtc, isTrue);
    });

    test('a new goal has no last contribution and percent 0', () {
      final goal = goalFromJson(_listItems()[0]);

      expect(goal.lastContribution, isNull);
      expect(goal.contributionCount, 0);
      expect(goal.saved, 0);
      expect(goal.percent, 0.0);
    });

    test('a goal without a deadline has null deadline fields', () {
      final goal = goalFromJson(_listItems()[2]);

      expect(goal.description, isNull);
      expect(goal.deadline, isNull);
      expect(goal.daysLeft, isNull);
      expect(goal.perMonthNeeded, isNull);
      expect(goal.percent, 25.0);
    });

    test('a reached goal past its deadline has daysLeft 0', () {
      final goal = goalFromJson(_listItems()[3]);

      expect(goal.percent, 100.0);
      expect(goal.remaining, 0);
      expect(goal.daysLeft, 0);
      expect(goal.perMonthNeeded, isNull);
      expect(goal.deadline, DateTime.utc(2026, 9, 30));
    });
  });

  group('mobile_goal_detail.json', () {
    test('parses the goal and its contributions newest first', () {
      final detail = goalDetailFromJson(_detailGoal());

      expect(detail.goal, goalFromJson(_listItems()[1]));
      expect(detail.contributions.map((c) => c.id), [142, 130, 117, 101]);
      expect(
        detail.contributions.first,
        Contribution(
          id: 142,
          amount: 1200000,
          note: 'Sisa jajan Oktober',
          date: DateTime.utc(2026, 10, 28, 12, 45),
        ),
      );
    });

    test('a contribution without a note has a null note', () {
      final detail = goalDetailFromJson(_detailGoal());

      expect(detail.contributions[2].note, isNull);
      expect(detail.contributions[2].amount, 1500000);
    });

    test('an empty history parses to no contributions', () {
      final json = _detailGoal()..['contributions'] = <Object?>[];

      expect(goalDetailFromJson(json).contributions, isEmpty);
    });

    test('a missing contributions list is a format error', () {
      final json = _detailGoal()..remove('contributions');

      expect(() => goalDetailFromJson(json), throwsFormatException);
    });

    test('a contribution with a wrong type is a format error', () {
      final json = _detailGoal()
        ..['contributions'] = [
          {'id': 1, 'amount': '1000', 'note': null, 'date': _date},
        ];

      expect(() => goalDetailFromJson(json), throwsFormatException);
    });

    test('a contribution note key that is missing is a format error', () {
      final json = _detailGoal()
        ..['contributions'] = [
          {'id': 1, 'amount': 1000, 'date': _date},
        ];

      expect(() => goalDetailFromJson(json), throwsFormatException);
    });
  });

  group('nullable fields: null parses, missing or wrong type throws', () {
    const nullable = {
      'description': 'x',
      'deadline': '2027-04-30',
      'daysLeft': 1,
      'perMonthNeeded': 1,
      'lastContribution': {'date': _date, 'amount': 1},
    };

    for (final key in nullable.keys) {
      test('$key null', () {
        final goal = goalFromJson(_fullItem()..[key] = null);
        final values = {
          'description': goal.description,
          'deadline': goal.deadline,
          'daysLeft': goal.daysLeft,
          'perMonthNeeded': goal.perMonthNeeded,
          'lastContribution': goal.lastContribution,
        };

        expect(values[key], isNull);
        expect(
          values.entries.where((e) => e.key != key).map((e) => e.value),
          everyElement(isNotNull),
        );
      });

      test('$key missing', () {
        expect(
          () => goalFromJson(_fullItem()..remove(key)),
          throwsFormatException,
        );
      });

      test('$key wrong type', () {
        expect(
          () => goalFromJson(_fullItem()..[key] = true),
          throwsFormatException,
        );
      });
    }
  });

  group('required fields', () {
    const required = [
      'id',
      'title',
      'target',
      'saved',
      'percent',
      'remaining',
      'createdAt',
      'contributionCount',
    ];

    for (final key in required) {
      test('$key null is a format error', () {
        expect(
          () => goalFromJson(_fullItem()..[key] = null),
          throwsFormatException,
        );
      });
    }

    test('money as a decimal is a format error, not rounded', () {
      expect(
        () => goalFromJson(_fullItem()..['saved'] = 6200000.5),
        throwsFormatException,
      );
    });

    test('percent accepts an int and a decimal', () {
      expect(goalFromJson(_fullItem()..['percent'] = 41).percent, 41.0);
      expect(goalFromJson(_fullItem()..['percent'] = 41.3).percent, 41.3);
    });

    test('lastContribution with a missing amount is a format error', () {
      expect(
        () => goalFromJson(
          _fullItem()..['lastContribution'] = {'date': _date},
        ),
        throwsFormatException,
      );
    });
  });

  group('dates', () {
    test('createdAt must be an ISO-8601 UTC timestamp', () {
      for (final value in ['2026-06-01', '2026-06-01T03:15:00+07:00', 'x']) {
        expect(
          () => goalFromJson(_fullItem()..['createdAt'] = value),
          throwsFormatException,
          reason: value,
        );
      }
    });

    test('deadline must be a real YYYY-MM-DD calendar date', () {
      for (final value in ['2027-4-30', '2027-02-30', '2027-04-30T00:00:00Z']) {
        expect(
          () => goalFromJson(_fullItem()..['deadline'] = value),
          throwsFormatException,
          reason: value,
        );
      }
    });
  });
}

const _date = '2026-10-28T12:45:00.000Z';
