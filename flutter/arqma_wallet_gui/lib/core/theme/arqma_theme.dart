import 'package:flutter/material.dart';

import 'arqma_colors.dart';

ThemeData buildArqmaTheme() {
  const Color gold = ArqmaColors.arqmaGreenSolid;
  const Color onGold = Color(0xFF14110A);
  const Color surfaceDeep = Color(0xFF12100C);
  const Color scaffold = Color(0xFF0E0C09);

  final TextTheme textTheme =
      ThemeData(brightness: Brightness.dark).textTheme.apply(
            bodyColor: ArqmaColors.textPrimary,
            displayColor: ArqmaColors.textPrimary,
          );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: scaffold,
    colorScheme: const ColorScheme.dark(
      primary: gold,
      onPrimary: onGold,
      secondary: ArqmaColors.arqmaGreenDarkSolid,
      onSecondary: ArqmaColors.textPrimary,
      surface: surfaceDeep,
      surfaceContainerHighest: ArqmaColors.darkPanel,
      error: ArqmaColors.negative,
      onSurface: ArqmaColors.textPrimary,
      onSurfaceVariant: ArqmaColors.textSecondary,
      outline: ArqmaColors.outlineDefault,
      outlineVariant: ArqmaColors.outlineSubtle,
    ),
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0A0806),
      foregroundColor: ArqmaColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 90,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: ArqmaColors.textPrimary,
      ),
      iconTheme: IconThemeData(color: ArqmaColors.textSecondary, size: 22),
    ),
    dividerColor: ArqmaColors.dividerLine,
    dividerTheme: const DividerThemeData(
      color: ArqmaColors.dividerLine,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: ArqmaColors.darkPanel,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: ArqmaColors.outlineSubtle, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: onGold,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
        textStyle:
            const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: gold,
        side: const BorderSide(color: ArqmaColors.outlineBright, width: 1.1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: gold),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF14110E),
      hintStyle: TextStyle(
          color: ArqmaColors.textMuted.withValues(alpha: 0.88), fontSize: 14),
      labelStyle:
          const TextStyle(color: ArqmaColors.textSecondary, fontSize: 13),
      floatingLabelStyle: const TextStyle(color: ArqmaColors.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
            color: ArqmaColors.outlineDefault.withValues(alpha: 0.55)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
            color: ArqmaColors.outlineDefault.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: gold, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: ArqmaColors.negative, width: 1.2),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: ArqmaColors.textPrimary,
      unselectedLabelColor: ArqmaColors.textMuted,
      indicatorColor: gold,
      dividerColor: ArqmaColors.dividerLine,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: ArqmaColors.textSecondary,
      textColor: ArqmaColors.textPrimary,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: ArqmaColors.darkPanel,
      textStyle: TextStyle(color: ArqmaColors.textPrimary, fontSize: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ArqmaColors.darkPanel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: ArqmaColors.outlineDefault, width: 1),
      ),
      titleTextStyle: const TextStyle(
        color: ArqmaColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      contentTextStyle: const TextStyle(
          color: ArqmaColors.textSecondary, fontSize: 14, height: 1.35),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E1A12),
      contentTextStyle:
          const TextStyle(color: ArqmaColors.textPrimary, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: ArqmaColors.outlineSubtle),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(
          ArqmaColors.outlineBright.withValues(alpha: 0.65)),
      thickness: WidgetStateProperty.all(8),
      radius: const Radius.circular(4),
    ),
    iconTheme: const IconThemeData(color: ArqmaColors.textSecondary),
  );
}
