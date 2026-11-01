import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';

const String kApiBaseUrl = String.fromEnvironment(
  'TEPIRA_API_BASE_URL',
  defaultValue: 'https://tepira.asepsunarya.com/api',
);

/// Single dio instance for the tepira API. Repositories depend on this; screens never do.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: kApiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (error, handler) {
        final status = error.response?.statusCode;
        if (status == 401) {
          return handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              error: const UnauthorizedException(),
            ),
          );
        }
        if (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout) {
          return handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              error: const NetworkException(),
            ),
          );
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});
