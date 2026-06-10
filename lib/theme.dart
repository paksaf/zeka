import 'package:flutter/material.dart';

/// Zeka color tokens — same vocabulary as the web Zeka brand
/// (#9D4EDD purple, #00F5FF cyan, #0B0B1A navy, #2D2D44 panel).
class ZekaColors {
  ZekaColors._();
  static const purple = Color(0xFF9D4EDD);
  static const cyan = Color(0xFF00F5FF);
  static const navy = Color(0xFF0B0B1A);
  static const navyMid = Color(0xFF1A1A2E);
  static const panel = Color(0xFF2D2D44);
  static const text = Color(0xFFE8E4D8);
  static const muted = Color(0xFF9CA3AF);
}

class ZekaTheme {
  ZekaTheme._();

  static ThemeData get dark {
    const seed = ZekaColors.purple;
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        primary: ZekaColors.purple,
        secondary: ZekaColors.cyan,
        surface: ZekaColors.navyMid,
      ),
      scaffoldBackgroundColor: ZekaColors.navy,
      cardTheme: const CardThemeData(
        color: Color(0xFF202036),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: Color(0x22FFFFFF)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ZekaColors.purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: ZekaColors.text,
        displayColor: ZekaColors.text,
      ),
      iconTheme: const IconThemeData(color: ZekaColors.cyan),
    );
  }
}
