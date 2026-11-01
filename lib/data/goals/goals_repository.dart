import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../features/goals/model/goal.dart';
import '../api_client.dart';
import 'goal_dto.dart';

/// Reads and changes the signed-in user's goals. Every method throws an
/// [AppException] subclass on failure.
abstract interface class GoalsRepository {
  /// `GET /api/mobile/goals`, in server order (unfinished first).
  Future<List<Goal>> list();

  /// `GET /api/mobile/goals/{id}` with the deposit history.
  /// Throws [NotFoundException] for a missing goal or another user's goal.
  Future<GoalDetail> detail(int id);

  /// `POST /api/mobile/goals`.
  ///
  /// [deadline] is the user's local calendar date and is sent as
  /// `YYYY-MM-DD` from its own year, month and day fields. It is never
  /// converted to UTC first: in WIB (UTC+7) a local midnight is the previous
  /// day in UTC, so `toUtc()` would move the deadline back one day.
  Future<Goal> create({
    required String title,
    required int target,
    String? description,
    DateTime? deadline,
  });

  /// `POST /api/contribution` (multipart form). Callers reload [detail]
  /// afterwards; the endpoint returns no goal data.
  Future<void> contribute(int goalId, int amount, [String? note]);
}

/// Message when a success response does not match the contract.
const String kUnrecognizedResponseMessage = 'Jawaban server tidak dikenali.';

/// [GoalsRepository] for SPEC sections 3.2 to 3.5.
class ApiGoalsRepository implements GoalsRepository {
  ApiGoalsRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<List<Goal>> list() async {
    final body = await _send(() => _dio.get<Object?>('/mobile/goals'));
    return _parse(() {
      final goals = body['goals'];
      if (goals is! List) throw const FormatException('goals is not a list');
      return [for (final item in goals) goalFromJson(_object(item))];
    });
  }

  @override
  Future<GoalDetail> detail(int id) async {
    final body = await _send(() => _dio.get<Object?>('/mobile/goals/$id'));
    return _parse(() => goalDetailFromJson(_object(body['goal'])));
  }

  @override
  Future<Goal> create({
    required String title,
    required int target,
    String? description,
    DateTime? deadline,
  }) async {
    final body = await _send(
      () => _dio.post<Object?>(
        '/mobile/goals',
        data: {
          'title': title,
          'target': target,
          'description': description,
          'deadline': deadline == null ? null : _calendarDate(deadline),
        },
        options: Options(contentType: Headers.jsonContentType),
      ),
    );
    return _parse(() => goalFromJson(_object(body['goal'])));
  }

  @override
  Future<void> contribute(int goalId, int amount, [String? note]) async {
    // The legacy route does not use the `{ok, error, message}` envelope: it
    // answers `{success: true}` on 2xx and `{success: false, message}` with
    // 400/401/404/500. The API client maps failures by HTTP status, so a 2xx
    // means the deposit was stored and the body is not inspected.
    await _send(
      () => _dio.post<Object?>(
        '/contribution',
        data: FormData.fromMap({
          'goalId': '$goalId',
          'amount': '$amount',
          if (note != null) 'note': note,
        }),
      ),
    );
  }
}

/// Runs [request] and returns its JSON object body, rethrowing failures as
/// the [AppException] the API client mapped.
Future<Map<String, Object?>> _send(
  Future<Response<Object?>> Function() request,
) async {
  final Response<Object?> response;
  try {
    response = await request();
  } on DioException catch (error) {
    final mapped = error.error;
    throw mapped is AppException
        ? mapped
        : const ApiException('Permintaan gagal. Coba lagi.');
  }
  final body = response.data;
  if (body is Map) return body.cast<String, Object?>();
  throw const ServerException(message: kUnrecognizedResponseMessage);
}

T _parse<T>(T Function() parse) {
  try {
    return parse();
  } on FormatException {
    throw const ServerException(message: kUnrecognizedResponseMessage);
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  throw const FormatException('expected a JSON object');
}

String _calendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

final goalsRepositoryProvider = Provider<GoalsRepository>(
  (ref) => ApiGoalsRepository(dio: ref.watch(dioProvider)),
);
