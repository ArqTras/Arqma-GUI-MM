import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mobile_background_wallet_sync.dart';

/// iOS native `UIBackgroundTask` + `BGProcessingTask` bridge.
class IosBackgroundSync {
  IosBackgroundSync._();

  static const MethodChannel _channel =
      MethodChannel('com.arqma.wallet/ios_background_sync');

  static bool _handlerRegistered = false;

  static void registerHandler(MobileBackgroundWalletSync coordinator) {
    if (!Platform.isIOS || _handlerRegistered) {
      return;
    }
    _handlerRegistered = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'backgroundTaskExpiring':
          await coordinator.handleBackgroundTaskExpiring();
          return null;
        case 'performBackgroundWalletSync':
          await coordinator.performBackgroundPulse();
          return null;
        default:
          throw MissingPluginException('IosBackgroundSync: ${call.method}');
      }
    });
  }

  static Future<int?> beginBackgroundSync() async {
    if (!Platform.isIOS) {
      return null;
    }
    try {
      final Object? key = await _channel.invokeMethod<Object>('beginBackgroundSync');
      if (key is int) {
        return key;
      }
      return int.tryParse('$key');
    } catch (e, st) {
      debugPrint('[IosBackgroundSync] beginBackgroundSync: $e\n$st');
      return null;
    }
  }

  static Future<void> endBackgroundSync(int taskKey) async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'endBackgroundSync',
        <String, dynamic>{'taskKey': taskKey},
      );
    } catch (e, st) {
      debugPrint('[IosBackgroundSync] endBackgroundSync: $e\n$st');
    }
  }

  static Future<void> scheduleProcessingSync() async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('scheduleProcessingSync');
    } catch (e, st) {
      debugPrint('[IosBackgroundSync] scheduleProcessingSync: $e\n$st');
    }
  }
}
