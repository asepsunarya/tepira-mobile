/// Parses expense JSON from `/api/mobile/expenses*` (SPEC-v2 §3.5 to 3.8).
library;

import '../../features/expenses/model/expense.dart';
import '../json_fields.dart';
import '../today/today_dto.dart';
import '../wallets/wallet_dto.dart';

/// One `expense` item (list, create and update answers).
Expense expenseFromJson(Map<String, Object?> json) {
  return Expense(
    id: requiredField<int>(json, 'id'),
    amount: requiredField<int>(json, 'amount'),
    category: nullableField<String>(json, 'category'),
    note: nullableField<String>(json, 'note'),
    source: requiredField<String>(json, 'source'),
    date: instantField(json, 'date'),
    createdAt: instantField(json, 'createdAt'),
    walletId: nullableField<int>(json, 'walletId'),
    walletName: nullableField<String>(json, 'walletName'),
    placeName: nullableField<String>(json, 'placeName'),
  );
}

/// The body of `GET /api/mobile/expenses`.
ExpenseList expenseListFromJson(Map<String, Object?> json) {
  return ExpenseList(
    asOf: instantField(json, 'asOf'),
    period: periodField(json, 'period'),
    total: requiredField<int>(json, 'total'),
    count: requiredField<int>(json, 'count'),
    more: requiredField<bool>(json, 'more'),
    expenses: listField(json, 'expenses', expenseFromJson),
  );
}

/// The body of `POST /api/mobile/expenses`, 201 or 200 (`deduped: true`).
ExpenseCreated expenseCreatedFromJson(Map<String, Object?> json) {
  final wallet = nullableField<Map<Object?, Object?>>(json, 'wallet');
  return ExpenseCreated(
    deduped: requiredField<bool>(json, 'deduped'),
    expense: expenseFromJson(objectField(json, 'expense')),
    wallet: wallet == null ? null : walletFromJson(jsonObject(wallet)),
    today: todaySummaryFromJson(objectField(json, 'today')),
  );
}

/// The body of `PATCH /api/mobile/expenses/{id}`.
ExpenseUpdated expenseUpdatedFromJson(Map<String, Object?> json) {
  return ExpenseUpdated(
    expense: expenseFromJson(objectField(json, 'expense')),
    wallets: listField(json, 'wallets', walletFromJson),
    today: todaySummaryFromJson(objectField(json, 'today')),
  );
}

/// The body of `DELETE /api/mobile/expenses/{id}`.
ExpenseDeleted expenseDeletedFromJson(Map<String, Object?> json) {
  final deleted = objectField(json, 'deleted');
  final wallet = nullableField<Map<Object?, Object?>>(json, 'wallet');
  return ExpenseDeleted(
    id: requiredField<int>(deleted, 'id'),
    amount: requiredField<int>(deleted, 'amount'),
    wallet: wallet == null ? null : walletFromJson(jsonObject(wallet)),
    today: todaySummaryFromJson(objectField(json, 'today')),
  );
}
