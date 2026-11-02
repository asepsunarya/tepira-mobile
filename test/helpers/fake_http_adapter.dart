import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// dio adapter that records requests and answers with a canned response, or
/// fails with a transport error of [failWith] type.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter({
    this.status = 200,
    this.body = const {'ok': true},
    this.headers = const {},
  });

  FakeHttpAdapter.failing(DioExceptionType this.failWith)
      : status = 0,
        body = null,
        headers = const {};

  final int status;
  final Object? body;

  /// Extra response headers, e.g. `{'retry-after': ['1']}`.
  final Map<String, List<String>> headers;
  DioExceptionType? failWith;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final failure = failWith;
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
