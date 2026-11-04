import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../features/today/model/today_summary.dart';
import '../api_call.dart';
import '../api_client.dart';
import 'today_dto.dart';

/// Reads the Desa summary. Throws an [AppException] subclass on failure.
abstract interface class TodayRepository {
  /// `GET /api/mobile/today`.
  Future<TodaySummary> get();
}

/// [TodayRepository] for SPEC-v2 §3.4.
class ApiTodayRepository implements TodayRepository {
  ApiTodayRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<TodaySummary> get() async {
    final body = await sendForObject(() => _dio.get<Object?>('/mobile/today'));
    return parseBody(() => todaySummaryFromJson(body));
  }
}

final todayRepositoryProvider = Provider<TodayRepository>(
  (ref) => ApiTodayRepository(dio: ref.watch(dioProvider)),
);
