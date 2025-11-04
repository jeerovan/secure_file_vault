import 'package:flutter/material.dart';

class AppThemes {
  static final lightTheme = ThemeData(
    fontFamily: 'Inter',
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.red, brightness: Brightness.light),
  );

  static final darkTheme = ThemeData(
    fontFamily: 'Inter',
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.red, brightness: Brightness.dark),
  );
}
