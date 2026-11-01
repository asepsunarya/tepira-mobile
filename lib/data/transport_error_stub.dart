/// Non-IO platforms (web): dio's browser adapter reports transport failures
/// as `connectionError`, so nothing extra to detect.
bool isTransportIoError(Object? error) => false;
