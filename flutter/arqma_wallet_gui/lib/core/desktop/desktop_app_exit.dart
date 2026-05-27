import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../app_exit_watchdog.dart';
import '../../app_nav.dart';
import '../services/desktop_native_bridge.dart';
import '../services/native_bridge.dart';

/// Stop wallet/daemon polling before showing the exit dialog (avoids new FFI work on UI).
void pauseBridgeTimersForExit(NativeBridge bridge) {
  if (bridge is DesktopNativeBridge) {
    bridge.stopTimersForExit();
  }
}

/// Full-screen "Shutting down…" after the modal route is gone.
void scheduleQuitPage() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final BuildContext? ctx = appNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      GoRouter.of(ctx).go('/quit');
    }
  });
}

/// Kill the process immediately; teardown runs in the background (must not block UI).
void hardExitFromApp(NativeBridge bridge) {
  unawaited(startAppExitWatchdog(maxSeconds: 3));
  pauseBridgeTimersForExit(bridge);
  unawaited(Future<void>(() async {
    try {
      await bridge
          .invoke('confirm_close', <String, dynamic>{'restart': false})
          .timeout(const Duration(milliseconds: 800));
    } catch (e, st) {
      debugPrint('[DesktopAppExit] confirm_close: $e\n$st');
    }
  }));
  terminateDesktopProcessNow();
}

void terminateDesktopProcessNow() {
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
