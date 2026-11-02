import 'dart:async';

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

/// Auth.js session cookie name over plain http (local dev). The mobile token
/// is the same JWE the web uses.
const String kSessionCookieName = 'authjs.session-token';

/// Auth.js session cookie name over https (production): Auth.js adds the
/// `__Secure-` prefix when the site is served securely.
const String kSecureSessionCookieName = '__Secure-$kSessionCookieName';

/// The Auth.js session cookie name the backend at [apiBaseUrl] expects:
/// [kSecureSessionCookieName] for https, [kSessionCookieName] otherwise.
String sessionCookieNameFor(Uri apiBaseUrl) =>
    apiBaseUrl.scheme.toLowerCase() == 'https'
        ? kSecureSessionCookieName
        : kSessionCookieName;

/// Request `extra` key: when true, a 401 answer is not reported to
/// [UnauthorizedEvents]. Set by the sign-in request, whose 401 means "invalid
/// Google token", not "session expired".
const String kSkipUnauthorizedEvent = 'tepira.skipUnauthorizedEvent';

/// Request `extra` key: the session token [SessionCookieInterceptor] read for
/// this request (null when none). [UnauthorizedInterceptor] uses it to ignore
/// a late 401 for a session that has already been replaced or ended.
const String kSessionTokenExtra = 'tepira.sessionToken';

/// Broadcasts every 401 from the API so the auth layer can end the session,
/// whichever repository made the request.
class UnauthorizedEvents {
  final _controller = StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;

  void notify() => _controller.add(null);

  Future<void> close() => _controller.close();
}

final unauthorizedEventsProvider = Provider<UnauthorizedEvents>((ref) {
  final events = UnauthorizedEvents();
  ref.onDispose(events.close);
  return events;
});

/// Single dio instance for the tepira API. Repositories depend on this; screens never do.
final dioProvider = Provider<Dio>(
  (ref) => createApiDio(
    baseUrl: kApiBaseUrl,
    sessionStore: ref.watch(sessionStoreProvider),
    onUnauthorized: ref.watch(unauthorizedEventsProvider).notify,
  ),
);

/// Builds the API client. Failed requests surface as a [DioException] whose
/// `error` is an [AppException] subclass. [onUnauthorized] runs for every
/// [UnauthorizedException] unless the request opted out with
/// [kSkipUnauthorizedEvent].
Dio createApiDio({
  required String baseUrl,
  required SessionStore sessionStore,
  void Function()? onUnauthorized,
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
    if (onUnauthorized != null)
      UnauthorizedInterceptor(onUnauthorized, sessionStore: sessionStore),
  ]);
  return dio;
}

/// Calls [onUnauthorized] when a request fails with [UnauthorizedException].
/// Must run after [ErrorMappingInterceptor].
///
/// With a [sessionStore], the 401 is only reported when the request was sent
/// with the session token that is still stored: a late 401 for an old token
/// (the user signed out or in again meanwhile) must not end the new session.
/// A request sent without a token never reports: there was no session to end,
/// even when none is stored now either.
class UnauthorizedInterceptor extends Interceptor {
  UnauthorizedInterceptor(this.onUnauthorized, {this.sessionStore});

  final void Function() onUnauthorized;
  final SessionStore? sessionStore;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final extra = err.requestOptions.extra;
    final skip = extra[kSkipUnauthorizedEvent] == true;
    if (err.error is UnauthorizedException && !skip) {
      final store = sessionStore;
      if (store == null) {
        onUnauthorized();
      } else {
        final sent = extra[kSessionTokenExtra];
        String? current;
        try {
          current = await store.readToken();
        } on Object {
          // The stored token cannot be compared, so the session is not ended;
          // the caller still receives the UnauthorizedException below.
          current = null;
        }
        if (sent != null && sent == current) onUnauthorized();
      }
    }
    handler.next(err);
  }
}

/// Adds the Auth.js session cookie (`<name>=<token>`) to the `Cookie` header
/// when a session exists, and only for requests to the API origin (scheme,
/// host and port) so the token never leaks elsewhere or over plain HTTP.
///
/// The name follows the API base URL scheme (see [sessionCookieNameFor]):
/// `__Secure-authjs.session-token` for https, `authjs.session-token` for http.
/// Other caller-set cookies are kept; if the caller already set a cookie with
/// the same session name, the caller's value wins.
class SessionCookieInterceptor extends Interceptor {
  SessionCookieInterceptor({
    required this.sessionStore,
    required this.apiBaseUrl,
  });

  final SessionStore sessionStore;
  final Uri apiBaseUrl;

  /// Session cookie name for [apiBaseUrl].
  String get cookieName => sessionCookieNameFor(apiBaseUrl);

  bool _isApiOrigin(Uri uri) =>
      uri.scheme.toLowerCase() == apiBaseUrl.scheme.toLowerCase() &&
      uri.host.toLowerCase() == apiBaseUrl.host.toLowerCase() &&
      uri.port == apiBaseUrl.port;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.extra[kSessionTokenExtra] = null;
    if (_isApiOrigin(options.uri)) {
      final token = await sessionStore.readToken();
      options.extra[kSessionTokenExtra] = token;
      if (token != null && token.isNotEmpty) {
        options.headers['Cookie'] = _withSessionCookie(
          options.headers['Cookie'],
          cookieName,
          token,
        );
      }
    }
    handler.next(options);
  }
}

String _withSessionCookie(Object? existing, String name, String token) {
  final current =
      existing is Iterable ? existing.join('; ') : (existing?.toString() ?? '');
  final pairs = current
      .split(';')
      .map((pair) => pair.trim())
      .where((pair) => pair.isNotEmpty)
      .toList();
  final hasSession = pairs.any(
    (pair) => pair.split('=').first.trim() == name,
  );
  if (!hasSession) pairs.add('$name=$token');
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
      // TLS certificate rejected: the user sees a connection problem.
      return const NetworkException();
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
  if (status == 400) {
    return BadRequestException(
      code: code is String ? code : 'bad_request',
      message: message is String ? message : null,
    );
  }
  if (status == 413) {
    return message is String
        ? PayloadTooLargeException(message)
        : const PayloadTooLargeException();
  }
  if (status == 415) {
    return message is String
        ? UnsupportedMediaTypeException(message)
        : const UnsupportedMediaTypeException();
  }
  if (status == 429) {
    return RateLimitedException(
      message: message is String ? message : null,
      retryAfter: _retryAfterOf(error.response),
    );
  }
  if ((status != null && status >= 500) || fields['ok'] == false) {
    return _serverException(fields, status, _retryAfterOf(error.response));
  }
  return ApiException(
    message is String ? message : 'Permintaan gagal. Coba lagi.',
    statusCode: status,
  );
}

ServerException _serverException(
  Map<Object?, Object?> body,
  int? status, [
  Duration? retryAfter,
]) {
  final message = body['message'];
  final code = body['error'];
  return ServerException(
    message: message is String ? message : null,
    code: code is String ? code : null,
    statusCode: status,
    retryAfter: retryAfter,
  );
}

Duration? _retryAfterOf(Response<dynamic>? response) =>
    parseRetryAfter(response?.headers.value('retry-after'));

final _deltaSeconds = RegExp(r'^\d{1,6}$');

/// The wait in a `Retry-After` header. The tepira API always sends whole
/// seconds (`Retry-After: 1`); anything else (missing, an HTTP date, a
/// negative or absurdly large number) gives null, and callers fall back to
/// their own default.
Duration? parseRetryAfter(String? header) {
  final value = header?.trim();
  if (value == null || !_deltaSeconds.hasMatch(value)) return null;
  return Duration(seconds: int.parse(value));
}
