import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/mobile_native_bridge.dart';
import 'ios_background_sync.dart';

/// Keeps wallet daemon + heartbeat polling alive while iOS backgrounds the app
/// (screen off / app switcher) using `UIBackgroundTask` chaining and
/// `BGProcessingTask` when the system grants longer runs.
class MobileBackgroundWalletSync with WidgetsBindingObserver {
  MobileBackgroundWalletSync._(this._bridge);

  static MobileBackgroundWalletSync? _instance;

  static MobileBackgroundWalletSync? get instance => _instance;

  static void install(MobileNativeBridge bridge) {
    if (!Platform.isIOS) {
      return;
    }
    final MobileBackgroundWalletSync coord =
        _instance ??= MobileBackgroundWalletSync._(bridge);
    coord._bridge = bridge;
    IosBackgroundSync.registerHandler(coord);
    WidgetsBinding.instance.removeObserver(coord);
    WidgetsBinding.instance.addObserver(coord);
  }

  MobileNativeBridge _bridge;
  final Set<int> _activeIosTaskKeys = <int>{};
  bool _appInBackground = false;
  bool _backgroundTransitionInFlight = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isIOS) {
      return;
    }
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_onEnterBackground());
      case AppLifecycleState.resumed:
        unawaited(_onEnterForeground());
      case AppLifecycleState.detached:
        unawaited(_onEnterForeground());
    }
  }

  Future<void> _onEnterBackground() async {
    if (_appInBackground || _backgroundTransitionInFlight) {
      return;
    }
    if (!_bridge.isWalletOpenForBackgroundSync) {
      return;
    }
    _backgroundTransitionInFlight = true;
    try {
      _appInBackground = true;
      debugPrint('[MobileBackgroundWalletSync] enter background — keep wallet sync');
      await _beginIosBackgroundTask();
      await IosBackgroundSync.scheduleProcessingSync();
    } finally {
      _backgroundTransitionInFlight = false;
    }
  }

  Future<void> _onEnterForeground() async {
    if (!_appInBackground && _activeIosTaskKeys.isEmpty) {
      return;
    }
    _appInBackground = false;
    await _endAllIosBackgroundTasks();
    if (_bridge.isWalletOpenForBackgroundSync) {
      unawaited(_bridge.pulseBackgroundWalletSync());
    }
  }

  /// Called from native when a `UIBackgroundTask` is about to expire (~30–180 s).
  Future<void> handleBackgroundTaskExpiring() async {
    if (!_appInBackground || !_bridge.isWalletOpenForBackgroundSync) {
      await _endAllIosBackgroundTasks();
      return;
    }
    debugPrint('[MobileBackgroundWalletSync] iOS bg task expiring — chain sync');
    await _endAllIosBackgroundTasks();
    await _bridge.pulseBackgroundWalletSync();
    await _beginIosBackgroundTask();
    await IosBackgroundSync.scheduleProcessingSync();
  }

  /// Called from native `BGProcessingTask` when iOS wakes the app for wallet sync.
  Future<void> performBackgroundPulse() async {
    if (!_bridge.isWalletOpenForBackgroundSync) {
      return;
    }
    debugPrint('[MobileBackgroundWalletSync] BGProcessingTask wallet pulse');
    await _bridge.pulseBackgroundWalletSync();
    if (_appInBackground) {
      await _beginIosBackgroundTask();
    }
  }

  Future<void> _beginIosBackgroundTask() async {
    final int? key = await IosBackgroundSync.beginBackgroundSync();
    if (key != null) {
      _activeIosTaskKeys.add(key);
    }
  }

  Future<void> _endAllIosBackgroundTasks() async {
    if (_activeIosTaskKeys.isEmpty) {
      return;
    }
    final List<int> keys = _activeIosTaskKeys.toList();
    _activeIosTaskKeys.clear();
    for (final int key in keys) {
      await IosBackgroundSync.endBackgroundSync(key);
    }
  }
}
