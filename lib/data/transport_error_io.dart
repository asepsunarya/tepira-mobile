import 'dart:io';

/// Whether [error] is a dart:io transport failure (socket reset, TLS
/// handshake, connection closed mid-response).
bool isTransportIoError(Object? error) =>
    error is SocketException || error is TlsException || error is HttpException;
