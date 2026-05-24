import 'dart:async';

import 'package:flutter/material.dart';

import '../app_nav.dart';
import '../core/theme/arqma_colors.dart';

/// Simple global loading counter (parity with Quasar `Loading.show` / `hide`).
class AppLoading {
  AppLoading._();
  static int _depth = 0;

  /// Schedules the dialog, then yields so the frame can paint before callers
  /// `await` heavy work (e.g. FFI `open_wallet`) on the same isolate.
  static Future<void> show() async {
    _depth++;
    if (_depth != 1) {
      return;
    }
    final BuildContext? c = appNavigatorKey.currentContext;
    if (c == null) {
      _depth--;
      return;
    }
    unawaited(
      showDialog<void>(
        context: c,
        useRootNavigator: true,
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
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 32));
  }

  static void hide() {
    if (_depth <= 0) {
      return;
    }
    _depth--;
    if (_depth == 0) {
      final BuildContext? c = appNavigatorKey.currentContext;
      if (c != null) {
        final NavigatorState nav = Navigator.of(c, rootNavigator: true);
        if (nav.canPop()) {
          nav.pop();
        }
      }
    }
  }
}
