import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/wib.dart';
import '../../features/expenses/model/expense.dart';
import '../../features/expenses/model/expense_input.dart';
import '../api_call.dart';
import '../api_client.dart';
import 'expense_dto.dart';

/// Reads and changes the signed-in user's expenses ("jajan"). Every method
/// throws an [AppException] subclass on failure.
abstract interface class ExpensesRepository {
  /// `POST /api/mobile/expenses`. A dedupe answer (200, `deduped: true`) is
  /// a success like a new row (201). Throws [BadRequestException] with code
  /// `wallet_not_found` when the wallet is gone or not the user's.
  Future<ExpenseCreated> create(NewExpense expense);

  /// `GET /api/mobile/expenses` for [month], or the current WIB month when
  /// null.
  Future<ExpenseList> list({WibMonth? month});

  /// `PATCH /api/mobile/expenses/{id}` with only the changed fields. Throws
  /// [NotFoundException] for a missing expense or another user's expense.
  Future<ExpenseUpdated> update(int id, ExpensePatch patch);

  /// `DELETE /api/mobile/expenses/{id}`. Throws [NotFoundException] when it
  /// is already gone.
  Future<ExpenseDeleted> delete(int id);
}

/// [ExpensesRepository] for SPEC-v2 §3.5 to 3.8.
class ApiExpensesRepository implements ExpensesRepository {
  ApiExpensesRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  static final _json = Options(contentType: Headers.jsonContentType);

  @override
  Future<ExpenseCreated> create(NewExpense expense) async {
    final body = await sendForObject(
      () => _dio.post<Object?>(
        '/mobile/expenses',
        data: expense.toJson(),
        options: _json,
      ),
    );
    return parseBody(() => expenseCreatedFromJson(body));
  }

  @override
  Future<ExpenseList> list({WibMonth? month}) async {
    final body = await sendForObject(
      () => _dio.get<Object?>(
        '/mobile/expenses',
        queryParameters: month == null
            ? null
            : {'year': '${month.year}', 'month': '${month.month}'},
      ),
    );
    return parseBody(() => expenseListFromJson(body));
  }

  @override
  Future<ExpenseUpdated> update(int id, ExpensePatch patch) async {
    final body = await sendForObject(
      () => _dio.patch<Object?>(
        '/mobile/expenses/$id',
        data: patch.toJson(),
        options: _json,
      ),
    );
    return parseBody(() => expenseUpdatedFromJson(body));
  }

  @override
  Future<ExpenseDeleted> delete(int id) async {
    final body = await sendForObject(
      () => _dio.delete<Object?>('/mobile/expenses/$id'),
    );
    return parseBody(() => expenseDeletedFromJson(body));
  }
}

final expensesRepositoryProvider = Provider<ExpensesRepository>(
  (ref) => ApiExpensesRepository(dio: ref.watch(dioProvider)),
);
