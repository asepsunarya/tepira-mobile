import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

/// Keeps tests offline and deterministic: Nunito comes from assets/fonts only.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
