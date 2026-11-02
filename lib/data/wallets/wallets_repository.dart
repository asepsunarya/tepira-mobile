import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../features/wallets/model/wallet.dart';
import '../../features/wallets/model/wallet_input.dart';
import '../api_client.dart';
import '../goals/goals_repository.dart' show kUnrecognizedResponseMessage;
import '../json_fields.dart';
import 'wallet_dto.dart';

/// Reads and changes the signed-in user's wallets. Every method throws an
/// [AppException] subclass on failure.
abstract interface class WalletsRepository {
  /// `GET /api/mobile/wallets`, in server order (`sortOrder`, then age).
  Future<WalletList> list();

  /// `POST /api/mobile/wallets`. Throws [BadRequestException] with the
  /// server's message when a rule fails.
  Future<WalletWrite> create(NewWallet wallet);

  /// `PATCH /api/mobile/wallets/{id}` with only the changed fields. Throws
  /// [NotFoundException] for a missing wallet or another user's wallet.
  Future<WalletWrite> update(int id, WalletPatch patch);
}

/// [WalletsRepository] for SPEC-v2 §3.1 to 3.3.
class ApiWalletsRepository implements WalletsRepository {
  ApiWalletsRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  static final _json = Options(contentType: Headers.jsonContentType);

  @override
  Future<WalletList> list() async {
    final body = await _send(() => _dio.get<Object?>('/mobile/wallets'));
    return _parse(() => walletListFromJson(body));
  }

  @override
  Future<WalletWrite> create(NewWallet wallet) async {
    final body = await _send(
      () => _dio.post<Object?>(
        '/mobile/wallets',
        data: wallet.toJson(),
        options: _json,
      ),
    );
    return _parse(() => walletWriteFromJson(body));
  }

  @override
  Future<WalletWrite> update(int id, WalletPatch patch) async {
    final body = await _send(
      () => _dio.patch<Object?>(
        '/mobile/wallets/$id',
        data: patch.toJson(),
        options: _json,
      ),
    );
    return _parse(() => walletWriteFromJson(body));
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
  return _parse(() => jsonObject(response.data, 'body'));
}

T _parse<T>(T Function() parse) {
  try {
    return parse();
  } on FormatException {
    throw const ServerException(message: kUnrecognizedResponseMessage);
  }
}

final walletsRepositoryProvider = Provider<WalletsRepository>(
  (ref) => ApiWalletsRepository(dio: ref.watch(dioProvider)),
);
