import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_exit_watchdog.dart';
import '../services/native_bridge.dart';

/// Desktop shutdown: schedule native teardown, then [exit] quickly.
///
/// Never await wallet FFI on the UI isolate ([save_wallet] / `store` block forever while
/// scanning). A background isolate watchdog kills the process if [exit] does not run.
Future<void> runDesktopGracefulExit(NativeBridge bridge) async {
  unawaited(startAppExitWatchdog(maxSeconds: 10));
  unawaited(Future<void>(() async {
    try {
      await bridge
          .invoke('confirm_close', <String, dynamic>{'restart': false})
          .timeout(const Duration(seconds: 1));
    } catch (e, st) {
      debugPrint('[DesktopAppExit] confirm_close: $e\n$st');
    }
  }));
  await Future<void>.delayed(const Duration(milliseconds: 80));
  try {
    exit(0);
  } catch (e, st) {
    debugPrint('[DesktopAppExit] exit(0): $e\n$st');
  }
}
