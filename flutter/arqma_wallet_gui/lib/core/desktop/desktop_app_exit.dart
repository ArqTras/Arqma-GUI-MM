import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../app_exit_watchdog.dart';
import '../app_nav.dart';
import '../services/native_bridge.dart';

/// Navigate to `/quit` after the exit dialog route is gone, then terminate the process.
void scheduleQuitPageAndExit(NativeBridge bridge) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final BuildContext? ctx = appNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      GoRouter.of(ctx).go('/quit');
    }
    unawaited(runDesktopGracefulExit(bridge));
  });
}

/// Stop timers/daemon synchronously, schedule FFI teardown in background, then exit immediately.
///
/// Never await wallet FFI on the UI isolate — `store` / `close_wallet` block forever while scanning.
Future<void> runDesktopGracefulExit(NativeBridge bridge) async {
  unawaited(startAppExitWatchdog(maxSeconds: 8));
  try {
    // Runs the synchronous body of [DesktopNativeBridge.invoke] `confirm_close` now.
    bridge.invoke('confirm_close', <String, dynamic>{'restart': false});
  } catch (e, st) {
    debugPrint('[DesktopAppExit] confirm_close: $e\n$st');
  }
  _terminateProcessNow();
}

void _terminateProcessNow() {
  try {
    exit(0);
  } catch (e, st) {
    debugPrint('[DesktopAppExit] exit(0): $e\n$st');
  }
  try {
    SystemNavigator.pop();
  } catch (e, st) {
    debugPrint('[DesktopAppExit] SystemNavigator.pop: $e\n$st');
  }
  try {
    Process.killPid(pid, ProcessSignal.sigkill);
  } catch (_) {}
}
