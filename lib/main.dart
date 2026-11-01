import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';

void main() {
  // Nunito is bundled in assets/fonts; never download fonts at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const ProviderScope(child: TepiraApp()));
}
