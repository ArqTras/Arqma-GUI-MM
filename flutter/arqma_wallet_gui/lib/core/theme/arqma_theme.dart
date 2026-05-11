import 'package:flutter/material.dart';

import 'arqma_colors.dart';

ThemeData buildArqmaTheme() {
  const Color gold = ArqmaColors.arqmaGreenSolid;
  const Color onGold = Color(0xFF14110A);
  const Color surfaceDeep = Color(0xFF12100C);
  const Color scaffold = Color(0xFF0E0C09);

  final TextTheme textTheme =
      ThemeData(brightness: Brightness.dark, useMaterial3: true)
          .textTheme
          .apply(
            bodyColor: ArqmaColors.textSecondary,
            displayColor: ArqmaColors.arqmaGreenSolid,
          );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: scaffold,
    colorScheme: const ColorScheme.dark(
      primary: gold,
      onPrimary: onGold,
      primaryContainer: Color(0xFF2E2818),
      onPrimaryContainer: gold,
      secondary: ArqmaColors.arqmaGreenDarkSolid,
      onSecondary: ArqmaColors.arqmaGreenSolid,
      secondaryContainer: Color(0xFF252018),
      onSecondaryContainer: gold,
      tertiary: gold,
      onTertiary: onGold,
      tertiaryContainer: Color(0xFF2E2818),
      onTertiaryContainer: gold,
      surface: surfaceDeep,
      surfaceContainerHighest: ArqmaColors.darkPanel,
      error: ArqmaColors.negative,
      onSurface: ArqmaColors.textSecondary,
      onSurfaceVariant: ArqmaColors.arqmaGreenDarkSolid,
      outline: ArqmaColors.outlineDefault,
      outlineVariant: ArqmaColors.outlineSubtle,
    ),
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0A0806),
      foregroundColor: ArqmaColors.arqmaGreenSolid,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 90,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: ArqmaColors.arqmaGreenSolid,
      ),
      iconTheme: IconThemeData(color: ArqmaColors.arqmaGreenSolid, size: 22),
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
      surfaceTintColor: Colors.transparent,
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
      labelColor: ArqmaColors.arqmaGreenSolid,
      unselectedLabelColor: ArqmaColors.arqmaGreenDarkSolid,
      indicatorColor: gold,
      dividerColor: ArqmaColors.dividerLine,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: ArqmaColors.arqmaGreenDarkSolid,
      textColor: ArqmaColors.arqmaGreenSolid,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: gold,
      foregroundColor: onGold,
      elevation: 2,
      shape: CircleBorder(),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: gold),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return ArqmaColors.textMuted;
          }
          if (states.contains(WidgetState.selected)) {
            return gold;
          }
          return ArqmaColors.textSecondary;
        },
      ),
      trackColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return ArqmaColors.outlineSubtle;
          }
          if (states.contains(WidgetState.selected)) {
            return gold.withValues(alpha: 0.38);
          }
          return ArqmaColors.outlineSubtle;
        },
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return ArqmaColors.textMuted;
          }
          if (states.contains(WidgetState.selected)) {
            return gold;
          }
          return Colors.transparent;
        },
      ),
      checkColor: WidgetStateProperty.all<Color>(onGold),
      side: const BorderSide(color: ArqmaColors.outlineBright, width: 1.4),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: ArqmaColors.darkPanel,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(
        color: ArqmaColors.arqmaGreenSolid,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
        TextStyle(
          color: ArqmaColors.arqmaGreenSolid,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      iconColor: ArqmaColors.arqmaGreenDarkSolid,
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.disabled)) {
              return ArqmaColors.textMuted;
            }
            return ArqmaColors.arqmaGreenSolid;
          },
        ),
      ),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(
        color: ArqmaColors.arqmaGreenSolid,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color?>(ArqmaColors.darkPanel),
        surfaceTintColor: WidgetStatePropertyAll<Color?>(Colors.transparent),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ArqmaColors.darkPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ArqmaColors.outlineDefault),
      ),
      textStyle: const TextStyle(
        color: ArqmaColors.arqmaGreenSolid,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ArqmaColors.darkPanel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: ArqmaColors.outlineDefault, width: 1),
      ),
      titleTextStyle: const TextStyle(
        color: ArqmaColors.arqmaGreenSolid,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
          color: ArqmaColors.textSecondary, fontSize: 14, height: 1.35),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E1A12),
      contentTextStyle:
          const TextStyle(color: ArqmaColors.arqmaGreenSolid, fontSize: 14),
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
    iconTheme: const IconThemeData(color: ArqmaColors.arqmaGreenDarkSolid),
  );
}
