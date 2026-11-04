import '../../../core/wib.dart';
import 'expense.dart';

/// Smallest and largest expense the API accepts (SPEC-v2 §3.5).
const int kMinExpenseAmount = 1;
const int kMaxExpenseAmount = 100000000;

/// Longest note the API accepts.
const int kMaxExpenseNoteLength = 120;

/// The server's message for an amount outside the range, shown as is when the
/// form rejects one before sending.
const String kExpenseAmountMessage =
    'Nominal harus berupa angka bulat antara 1 dan 100.000.000.';

/// `source`: which money paid for the expense. [gaji] is the default.
enum ExpenseSource {
  gaji,
  bonus;

  String get wire => name;
}

/// Body of `POST /api/mobile/expenses` (SPEC-v2 §3.5).
class NewExpense {
  const NewExpense({
    required this.amount,
    required this.walletId,
    this.category,
    this.note,
    this.source = ExpenseSource.gaji,
    this.day,
  });

  /// 1..[kMaxExpenseAmount].
  final int amount;
  final int walletId;

  /// A category label, or null for none.
  final String? category;

  /// Blank means none.
  final String? note;
  final ExpenseSource source;

  /// WIB day as `YYYY-MM-DD`, or null for today. The app never sends
  /// today's date: a resend after midnight WIB would then mean "yesterday"
  /// and escape the server's 120 s dedupe.
  final String? day;

  Map<String, Object?> toJson() => {
        'amount': amount,
        'walletId': walletId,
        'category': category,
        'note': _blankToNull(note),
        'source': source.wire,
        if (day != null) 'date': day,
      };
}

/// The fields an expense form holds when the user saves an edit.
class ExpenseEdit {
  const ExpenseEdit({
    required this.amount,
    required this.walletId,
    required this.category,
    required this.note,
    required this.source,
    required this.day,
  });

  final int amount;
  final int walletId;
  final String? category;

  /// Blank means none.
  final String? note;

  /// The picked source, or null when none is picked (a stored source the app
  /// does not know), which keeps the stored one.
  final ExpenseSource? source;

  /// WIB day as `YYYY-MM-DD`.
  final String day;
}

/// Body of `PATCH /api/mobile/expenses/{id}`: only the fields that changed
/// (SPEC-v2 §3.7). A category or note the user cleared is sent as `null`.
class ExpensePatch {
  const ExpensePatch._(this._fields);

  /// The difference between [original] and [edit]. The day is compared in
  /// WIB, so an unchanged day keeps the stored time.
  factory ExpensePatch.between(Expense original, ExpenseEdit edit) {
    final note = _blankToNull(edit.note);
    return ExpensePatch._({
      if (edit.amount != original.amount) 'amount': edit.amount,
      if (edit.walletId != original.walletId) 'walletId': edit.walletId,
      if (edit.category != original.category) 'category': edit.category,
      if (note != original.note) 'note': note,
      if (edit.source case final source? when source.wire != original.source)
        'source': source.wire,
      if (edit.day != wibDayKey(original.date)) 'date': edit.day,
    });
  }

  final Map<String, Object?> _fields;

  /// Nothing changed; the server would answer "Tidak ada perubahan.".
  bool get isEmpty => _fields.isEmpty;

  Map<String, Object?> toJson() => Map.unmodifiable(_fields);
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
