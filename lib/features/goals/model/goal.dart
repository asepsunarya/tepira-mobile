import 'package:flutter/foundation.dart';

/// A savings goal ("kavling") as the API reports it. Money is int rupiah;
/// [percent] comes from the server and is never recomputed on the client.
@immutable
class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.saved,
    required this.percent,
    required this.remaining,
    required this.deadline,
    required this.daysLeft,
    required this.perMonthNeeded,
    required this.createdAt,
    required this.lastContribution,
    required this.contributionCount,
  });

  final int id;
  final String title;
  final String? description;
  final int target;
  final int saved;

  /// 0 to 100, may have one decimal (e.g. 41.3).
  final double percent;
  final int remaining;

  /// Calendar date (WIB) at UTC midnight, or null without a deadline.
  final DateTime? deadline;

  /// Null without a deadline; 0 once the deadline has passed.
  final int? daysLeft;

  /// Null without a deadline or once the goal is reached.
  final int? perMonthNeeded;
  final DateTime createdAt;
  final LastContribution? lastContribution;
  final int contributionCount;

  @override
  bool operator ==(Object other) =>
      other is Goal &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.target == target &&
      other.saved == saved &&
      other.percent == percent &&
      other.remaining == remaining &&
      other.deadline == deadline &&
      other.daysLeft == daysLeft &&
      other.perMonthNeeded == perMonthNeeded &&
      other.createdAt == createdAt &&
      other.lastContribution == lastContribution &&
      other.contributionCount == contributionCount;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        description,
        target,
        saved,
        percent,
        remaining,
        deadline,
        daysLeft,
        perMonthNeeded,
        createdAt,
        lastContribution,
        contributionCount,
      );
}

/// The newest deposit of a goal, shown on the goal list.
@immutable
class LastContribution {
  const LastContribution({required this.date, required this.amount});

  final DateTime date;
  final int amount;

  @override
  bool operator ==(Object other) =>
      other is LastContribution && other.date == date && other.amount == amount;

  @override
  int get hashCode => Object.hash(date, amount);
}

/// One deposit ("setoran") in a goal's history.
@immutable
class Contribution {
  const Contribution({
    required this.id,
    required this.amount,
    required this.note,
    required this.date,
  });

  final int id;
  final int amount;
  final String? note;
  final DateTime date;

  @override
  bool operator ==(Object other) =>
      other is Contribution &&
      other.id == id &&
      other.amount == amount &&
      other.note == note &&
      other.date == date;

  @override
  int get hashCode => Object.hash(id, amount, note, date);
}

/// A goal with its deposit history, newest first (at most 200 entries;
/// [Goal.saved] and [Goal.contributionCount] still count all of them).
@immutable
class GoalDetail {
  const GoalDetail({required this.goal, required this.contributions});

  final Goal goal;
  final List<Contribution> contributions;

  @override
  bool operator ==(Object other) =>
      other is GoalDetail &&
      other.goal == goal &&
      listEquals(other.contributions, contributions);

  @override
  int get hashCode => Object.hash(goal, Object.hashAll(contributions));
}
