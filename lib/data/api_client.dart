import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import 'session_store.dart';
import 'transport_error_stub.dart'
    if (dart.library.io) 'transport_error_io.dart';

const String kApiBaseUrl = String.fromEnvironment(
  'TEPIRA_API_BASE_URL',
  defaultValue: 'https://tepira.asepsunarya.com/api',
);

/// Auth.js cookie name; the mobile token is the same JWE the web uses.
const String kSessionCookieName = 'authjs.session-token';

/// Single dio instance for the tepira API. Repositories depend on this; screens never do.
final dioProvider = Provider<Dio>(
  (ref) => createApiDio(
    baseUrl: kApiBaseUrl,
    sessionStore: ref.watch(sessionStoreProvider),
  ),
);

/// Builds the API client. Failed requests surface as a [DioException] whose
/// `error` is an [AppException] subclass.
Dio createApiDio({
  required String baseUrl,
  required SessionStore sessionStore,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.addAll([
    SessionCookieInterceptor(
      sessionStore: sessionStore,
      apiBaseUrl: Uri.parse(baseUrl),
    ),
    ErrorMappingInterceptor(),
  ]);
  return dio;
}

/// Adds `authjs.session-token=<token>` to the `Cookie` header when a session
/// exists, and only for requests to the API origin (scheme, host and port) so
/// the token never leaks elsewhere or over plain HTTP. Caller-set cookies are
/// kept.
class SessionCookieInterceptor extends Interceptor {
  SessionCookieInterceptor({
    required this.sessionStore,
    required this.apiBaseUrl,
  });

  final SessionStore sessionStore;
  final Uri apiBaseUrl;

  bool _isApiOrigin(Uri uri) =>
      uri.scheme.toLowerCase() == apiBaseUrl.scheme.toLowerCase() &&
      uri.host.toLowerCase() == apiBaseUrl.host.toLowerCase() &&
      uri.port == apiBaseUrl.port;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isApiOrigin(options.uri)) {
      final token = await sessionStore.readToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Cookie'] = _withSessionCookie(
          options.headers['Cookie'],
          '$kSessionCookieName=$token',
        );
      }
    }
    handler.next(options);
  }
}

String _withSessionCookie(Object? existing, String sessionCookie) {
  final current =
      existing is Iterable ? existing.join('; ') : (existing?.toString() ?? '');
  final pairs = current
      .split(';')
      .map((pair) => pair.trim())
      .where((pair) => pair.isNotEmpty)
      .toList();
  final hasSession = pairs.any(
    (pair) => pair.split('=').first.trim() == kSessionCookieName,
  );
  if (!hasSession) pairs.add(sessionCookie);
  return pairs.join('; ');
}

/// Maps transport and HTTP failures to [AppException] subclasses.
class ErrorMappingInterceptor extends Interceptor {
  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final body = response.data;
    if (body is Map && body['ok'] == false) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: _serverException(body, response.statusCode),
        ),
      );
      return;
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is AppException) {
      handler.next(err);
      return;
    }
    final mapped = mapDioException(err);
    if (mapped == null) {
      handler.next(err);
      return;
    }
    handler.next(err.copyWith(error: mapped));
  }
}

/// Returns the [AppException] for [error], or null when it is not one the
/// API contract defines (e.g. a cancelled request).
AppException? mapDioException(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.connectionError:
      return const NetworkException();
    case DioExceptionType.badResponse:
      break;
    case DioExceptionType.unknown:
      // dio only maps IO failures to connectionError while opening the
      // connection; a reset, TLS handshake failure or closed connection
      // mid-transfer arrives here as `unknown`.
      return isTransportIoError(error.error) ? const NetworkException() : null;
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
      return null;
  }

  final status = error.response?.statusCode;
  final body = error.response?.data;
  final fields = body is Map ? body : const <Object?, Object?>{};
  final message = fields['message'];
  final code = fields['error'];

  if (status == 401) return const UnauthorizedException();
  if (status == 403) {
    return ForbiddenException(
      message: message is String ? message : null,
      code: code is String ? code : null,
    );
  }
  if (status == 404) return const NotFoundException();
  if ((status != null && status >= 500) || fields['ok'] == false) {
    return _serverException(fields, status);
  }
  return ApiException(
    message is String ? message : 'Permintaan gagal. Coba lagi.',
    statusCode: status,
  );
}

ServerException _serverException(Map<Object?, Object?> body, int? status) {
  final message = body['message'];
  final code = body['error'];
  return ServerException(
    message: message is String ? message : null,
    code: code is String ? code : null,
    statusCode: status,
  );
}
