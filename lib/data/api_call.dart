/// Shared request and parse steps for the v2 repositories.
library;

import 'package:dio/dio.dart';

import '../core/errors.dart';
import 'goals/goals_repository.dart' show kUnrecognizedResponseMessage;
import 'json_fields.dart';

/// Runs [request] and returns its JSON object body, rethrowing failures as
/// the [AppException] the API client mapped.
Future<Map<String, Object?>> sendForObject(
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
  return parseBody(() => jsonObject(response.data, 'body'));
}

/// Runs [parse]; a body that breaks the contract becomes a
/// [ServerException] with "Jawaban server tidak dikenali.".
T parseBody<T>(T Function() parse) {
  try {
    return parse();
  } on FormatException {
    throw const ServerException(message: kUnrecognizedResponseMessage);
  }
}
