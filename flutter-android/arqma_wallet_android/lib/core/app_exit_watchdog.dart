import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Message: `[maxSeconds, ownPid]`.
@pragma('vm:entry-point')
void _appExitWatchdogMain(List<dynamic> args) {
  final int maxSeconds = (args[0] as num).toInt();
  final int ownPid = (args[1] as num).toInt();
  sleep(Duration(seconds: maxSeconds));
  stderr.writeln(
    '[ArqmaWallet] exit watchdog: forcing shutdown after ${maxSeconds}s '
    '(wallet native code blocked the UI thread — PID $ownPid)',
  );
  try {
    Process.killPid(ownPid, ProcessSignal.sigkill);
  } catch (_) {
    // ignore
  }
  try {
    exit(0);
  } catch (_) {
    // ignore
  }
}

/// Starts a hard kill timer on another isolate (still runs when the UI isolate
/// is stuck in synchronous wallet FFI — [Future.timeout] does not).
Future<AppExitWatchdog> startAppExitWatchdog({int maxSeconds = 14}) async {
  try {
    final Isolate i = await Isolate.spawn<List<dynamic>>(
      _appExitWatchdogMain,
      <dynamic>[maxSeconds, pid],
      errorsAreFatal: false,
    );
    return AppExitWatchdog._(i);
  } catch (e, st) {
    debugPrint('[AppExitWatchdog] spawn failed: $e\n$st');
    return AppExitWatchdog._(null);
  }
}

final class AppExitWatchdog {
  AppExitWatchdog._(this._isolate);

  final Isolate? _isolate;

  void cancel() {
    try {
      _isolate?.kill(priority: Isolate.immediate);
    } catch (_) {}
  }
}
