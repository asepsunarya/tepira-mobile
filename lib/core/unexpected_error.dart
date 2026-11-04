import 'package:flutter/material.dart';

/// Snackbar text for a save that failed with an error the app does not
/// handle (anything that is not an `AppException`: a bug, a parse error).
const String kUnexpectedErrorMessage = 'Terjadi kesalahan. Coba lagi.';

/// Tells the user a save failed unexpectedly, so the form coming back is
/// not silent. The caller still rethrows the error, so it reaches the zone
/// handler (and crash reporting) as before.
void showUnexpectedError(BuildContext context) {
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text(kUnexpectedErrorMessage)));
}
