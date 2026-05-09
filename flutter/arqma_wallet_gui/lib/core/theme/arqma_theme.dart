import 'package:flutter/material.dart';
import 'arqma_colors.dart';

ThemeData buildArqmaTheme() {
  const gold = ArqmaColors.arqmaGreenSolid;
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: ArqmaColors.black80,
    colorScheme: const ColorScheme.dark(
      primary: gold,
      secondary: ArqmaColors.black90,
      surface: ArqmaColors.black80,
      error: ArqmaColors.negative,
      onPrimary: Colors.black87,
      onSurface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ArqmaColors.headerBg,
      foregroundColor: Colors.white,
      elevation: 0,
      toolbarHeight: 90,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w300,
        color: Colors.white,
      ),
    ),
    dividerColor: Colors.white,
    cardTheme: CardThemeData(
      color: ArqmaColors.darkPanel,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: gold,
        side: const BorderSide(color: gold),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ArqmaColors.black90,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: gold, width: 1.4),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(ArqmaColors.scrollbar),
      thickness: WidgetStateProperty.all(8),
      radius: const Radius.circular(3),
    ),
  );
  return base;
}
