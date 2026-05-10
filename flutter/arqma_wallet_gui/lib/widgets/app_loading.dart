import 'package:flutter/material.dart';

import '../app_nav.dart';
import '../core/theme/arqma_colors.dart';

/// Simple global loading counter (parity with Quasar `Loading.show` / `hide`).
class AppLoading {
  AppLoading._();
  static int _depth = 0;

  static void show() {
    _depth++;
    if (_depth != 1) {
      return;
    }
    final BuildContext? c = appNavigatorKey.currentContext;
    if (c == null) {
      return;
    }
    showDialog<void>(
      context: c,
      barrierDismissible: false,
      builder: (BuildContext c) => Center(
        child: Card(
          color: const Color(0xFF161410),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: ArqmaColors.outlineBright.withValues(alpha: 0.65),
              width: 1,
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: ArqmaColors.arqmaGreenSolid,
            ),
          ),
        ),
      ),
    );
  }

  static void hide() {
    if (_depth <= 0) {
      return;
    }
    _depth--;
    if (_depth == 0) {
      final NavigatorState? nav = appNavigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.pop();
      }
    }
  }
}
