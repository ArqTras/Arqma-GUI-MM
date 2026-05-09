import 'package:flutter/material.dart';

import '../app_nav.dart';

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
      builder: (BuildContext c) => const Center(
        child: Card(
          color: Color(0xFF1d1d1d),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(strokeWidth: 2),
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
