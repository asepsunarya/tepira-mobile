/// Base class for user-facing errors. [message] is shown to the user in Indonesian.
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkException extends AppException {
  const NetworkException([super.message = 'Koneksi bermasalah. Coba lagi.']);
}

class UnauthorizedException extends AppException {
  const UnauthorizedException([
    super.message = 'Sesi berakhir. Masuk lagi, ya.',
  ]);
}

class ApiException extends AppException {
  const ApiException(super.message, {this.statusCode});

  final int? statusCode;
}
