/// Inline form error for a save that failed with an error the app does not
/// handle (anything that is not an `AppException`: a bug, a parse error).
///
/// The form shows it in its usual error line above the submit button, so
/// it never covers that button, and clears it like its other save errors.
/// The form still rethrows the error, so it is forwarded to the zone error
/// handler (and `FlutterError.onError` for framework errors) as before.
const String kUnexpectedErrorMessage = 'Terjadi kesalahan. Coba lagi.';
