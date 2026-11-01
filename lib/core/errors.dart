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

/// HTTP 404: the resource does not exist or does not belong to the user.
class NotFoundException extends AppException {
  const NotFoundException([super.message = 'Data tidak ditemukan.']);
}

/// HTTP 5xx, or any response whose body is `{ "ok": false }`.
class ServerException extends AppException {
  const ServerException({String? message, this.code, this.statusCode})
      : super(message ?? 'Server sedang bermasalah. Coba lagi nanti.');

  final String? code;
  final int? statusCode;
}

class ApiException extends AppException {
  const ApiException(super.message, {this.statusCode});

  final int? statusCode;
}

/// Message when Google sign-in fails for a reason the user cannot act on.
const String kGoogleSignInFailedMessage =
    'Masuk dengan Google gagal. Coba lagi.';
