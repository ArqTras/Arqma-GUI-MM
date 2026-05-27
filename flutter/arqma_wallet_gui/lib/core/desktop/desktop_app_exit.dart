import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_exit_watchdog.dart';
import '../services/desktop_native_bridge.dart';
import '../services/native_bridge.dart';

/// Graceful desktop shutdown: optional wallet flush, then [confirm_close] (daemon + FFI).
///
/// Skips [save_wallet] while a full rescan or Windows chain sync is in progress so exit
/// does not block the UI isolate on FFI. [confirm_close] still tears down timers, `arqmad`,
/// solo pool, and wallet session (see [DesktopNativeBridge.invoke]).
Future<void> runDesktopGracefulExit(NativeBridge bridge) async {
  // Keep armed until the process exits — canceling early removed the only recovery
  // when synchronous wallet FFI blocked the UI isolate after confirm_close.
  await startAppExitWatchdog(maxSeconds: 12);
  final bool skipSave = bridge is! DesktopNativeBridge ||
      bridge.shouldSkipSaveOnExit;
  if (!skipSave) {
    try {
      await bridge
          .backendSend('wallet', 'save_wallet', <String, dynamic>{})
          .timeout(const Duration(seconds: 2));
    } catch (e, st) {
      debugPrint('[DesktopAppExit] save_wallet: $e\n$st');
    }
  } else if (bridge is DesktopNativeBridge && !bridge.hasOpenWallet) {
    debugPrint('[DesktopAppExit] skipping save_wallet (no open wallet)');
  } else {
    debugPrint(
      '[DesktopAppExit] skipping save_wallet (rescan or Windows sync in progress)',
    );
  }
  try {
    await bridge
        .invoke('confirm_close', <String, dynamic>{'restart': false})
        .timeout(const Duration(seconds: 2));
  } catch (e, st) {
    debugPrint('[DesktopAppExit] confirm_close: $e\n$st');
  }
}
