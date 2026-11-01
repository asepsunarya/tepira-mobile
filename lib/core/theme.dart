import 'package:flutter/material.dart';

/// Dark-first theme matching the tepira.id web app.
final ThemeData tepiraTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF34D399),
    brightness: Brightness.dark,
  ),
);
