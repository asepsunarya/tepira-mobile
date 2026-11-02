/// Base class for user-facing errors. [message] is shown to the user in Indonesian.
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Timeout or no connection to the API.
class NetworkException extends AppException {
  const NetworkException([super.message = 'Koneksi bermasalah. Coba lagi.']);
}

/// HTTP 401: the session is missing, invalid, or expired.
class UnauthorizedException extends AppException {
  const UnauthorizedException([
    super.message = 'Sesi berakhir. Masuk lagi, ya.',
  ]);
}

/// HTTP 403. [code] is the API error code, e.g. `not_allowed` when the
/// Google account is outside the allowlist.
class ForbiddenException extends AppException {
  const ForbiddenException({String? message, this.code})
      : super(message ?? 'Kamu tidak punya akses ke data ini.');

  final String? code;
}

/// HTTP 400: the server rejected the request body. [message] is the server's
/// validation message, shown as is. [code] tells failures apart, e.g.
/// `bad_request` (validation) or `wallet_not_found` (the chosen wallet is
/// gone or not the user's).
class BadRequestException extends AppException {
  const BadRequestException({this.code = 'bad_request', String? message})
      : super(message ?? 'Permintaan tidak valid. Periksa lagi isiannya.');

  final String code;
}

/// HTTP 413: the request body is larger than the API accepts.
class PayloadTooLargeException extends AppException {
  const PayloadTooLargeException([
    super.message = 'Isi permintaan terlalu besar.',
  ]);
}

/// HTTP 415: the request was not sent as JSON.
class UnsupportedMediaTypeException extends AppException {
  const UnsupportedMediaTypeException([
    super.message = 'Format permintaan harus JSON.',
  ]);
}

/// HTTP 429: too many requests. [retryAfter] is the server's `Retry-After`
/// wait, or null when the header is missing or unreadable. Nothing was
/// written, so the same request can be sent again after the wait.
class RateLimitedException extends AppException {
  const RateLimitedException({String? message, this.retryAfter})
      : super(message ?? 'Terlalu banyak permintaan. Coba lagi sebentar lagi.');

  final Duration? retryAfter;
}

/// HTTP 404: the resource does not exist or does not belong to the user.
class NotFoundException extends AppException {
  const NotFoundException([super.message = 'Data tidak ditemukan.']);
}

/// HTTP 5xx, or any response whose body is `{ "ok": false }`.
///
/// [retryAfter] is set when the server sent `Retry-After` (a database
/// deadlock or serialization abort): nothing was written and the same
/// request can be sent again after the wait.
class ServerException extends AppException {
  const ServerException({
    String? message,
    this.code,
    this.statusCode,
    this.retryAfter,
  }) : super(message ?? 'Server sedang bermasalah. Coba lagi nanti.');

  final String? code;
  final int? statusCode;
  final Duration? retryAfter;
}

/// True for HTTP 502/503/504: the gateway lost the upstream, so the request
/// may or may not have been processed. Callers should treat it like a
/// [NetworkException] (outcome unknown), not as a definite failure.
bool isGatewayError(AppException error) =>
    error is ServerException &&
    const {502, 503, 504}.contains(error.statusCode);

class ApiException extends AppException {
  const ApiException(super.message, {this.statusCode});

  final int? statusCode;
}

/// Message when Google sign-in fails for a reason the user cannot act on.
const String kGoogleSignInFailedMessage =
    'Masuk dengan Google gagal. Coba lagi.';
