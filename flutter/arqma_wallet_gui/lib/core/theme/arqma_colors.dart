import 'package:flutter/material.dart';

/// Parity with `src/css/quasar.variables.scss` and `app.scss`.
abstract final class ArqmaColors {
  static const Color neutral = Color(0xFFE0E1E2);
  static const Color positive = Color(0xFFDBD19C);
  static const Color negative = Color(0xFFDB2828);
  static const Color info = Color(0xFF026DEC);
  static const Color warning = Color(0xFFF2C037);

  static const Color arqmaGreenSolid = Color(0xFFDBD19C);
  static const Color arqmaGreenDarkSolid = Color(0xFFA89060);
  static const Color arqmaListAccent = Color(0xFFA89060);

  static const Color black90 = Color(0xFF111111);
  static const Color black80 = Color(0xFF111111);
  static const Color headerBg = Color(0xFF0A0A0A);
  static const Color darkPanel = Color(0xFF1D1D1D);

  static const Color selection = Color.fromRGBO(168, 144, 96, 0.45);
  static const Color scrollbar = Color(0xFF646464);
  static const Color txIn = Color(0xFF43BD43);
  static const Color identiconBg = Color(0xFFCB8FE1);

  static const Color footerBorder = Color.fromRGBO(167, 144, 96, 0.35);
  static const Color barTrack = Color(0xFF2A2A2A);

  /// Warm body text / chrome (replaces stark `Colors.white*` on dark panels).
  static const Color textPrimary = Color(0xFFF4ECDA);
  static const Color textSecondary = Color(0xFFC9B896);
  static const Color textMuted = Color(0xFF8A7D62);

  /// Gold-tinted borders and rules (replaces `Colors.white12` / `white24` dividers).
  static const Color outlineSubtle = Color(0xFF2E2A22);
  static const Color outlineDefault = Color(0xFF5C4F38);
  static const Color outlineBright = Color(0xFF9A8658);
  static const Color dividerLine = Color(0xFF3D3528);

  /// Behind QR modules (needs high contrast for scanners; warm off-white).
  static const Color qrLightSurface = Color(0xFFFFF8ED);
}
