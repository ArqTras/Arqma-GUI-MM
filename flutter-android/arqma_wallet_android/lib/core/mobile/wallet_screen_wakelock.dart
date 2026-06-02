import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device awake while the wallet UI is open (iOS: disables idle timer).
class WalletScreenWakelock {
  static bool _enabled = false;

  static Future<void> enable() async {
    if (kIsWeb || _enabled) {
      return;
    }
    try {
      await WakelockPlus.enable();
      _enabled = true;
    } catch (e, st) {
      debugPrint('[WalletScreenWakelock] enable: $e\n$st');
    }
  }

  static Future<void> disable() async {
    if (kIsWeb || !_enabled) {
      return;
    }
    try {
      await WakelockPlus.disable();
      _enabled = false;
    } catch (e, st) {
      debugPrint('[WalletScreenWakelock] disable: $e\n$st');
    }
  }
}
