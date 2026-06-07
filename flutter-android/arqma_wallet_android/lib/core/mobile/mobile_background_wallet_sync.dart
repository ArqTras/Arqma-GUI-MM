import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/mobile_native_bridge.dart';
import 'ios_background_sync.dart';

/// Keeps wallet daemon + heartbeat polling alive while the app is backgrounded
/// (screen off / app switcher).
///
/// iOS: `UIBackgroundTask` chaining + `BGProcessingTask` when the system grants longer runs.
/// Android: persist before suspend + periodic pulse while [AppLifecycleState.paused].
class MobileBackgroundWalletSync with WidgetsBindingObserver {
  MobileBackgroundWalletSync._(this._bridge);

  static MobileBackgroundWalletSync? _instance;

  static MobileBackgroundWalletSync? get instance => _instance;

  static void install(MobileNativeBridge bridge) {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return;
    }
    final MobileBackgroundWalletSync coord =
        _instance ??= MobileBackgroundWalletSync._(bridge);
    coord._bridge = bridge;
    if (Platform.isIOS) {
      IosBackgroundSync.registerHandler(coord);
    }
    WidgetsBinding.instance.removeObserver(coord);
    WidgetsBinding.instance.addObserver(coord);
  }

  MobileNativeBridge _bridge;
  final Set<int> _activeIosTaskKeys = <int>{};
  bool _appInBackground = false;
  bool _backgroundTransitionInFlight = false;
  Timer? _backgroundPulseTimer;

  static const Duration _kBackgroundPulseInterval = Duration(seconds: 5);

  bool get _isMobilePlatform => Platform.isIOS || Platform.isAndroid;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isMobilePlatform) {
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
      debugPrint(
          '[MobileBackgroundWalletSync] enter background — persist + keep sync');
      await _bridge.persistWalletBeforeSuspend(reason: 'enter_background');
      if (Platform.isIOS) {
        await _beginIosBackgroundTask();
        await IosBackgroundSync.scheduleProcessingSync();
      }
      _startBackgroundPulseLoop();
    } finally {
      _backgroundTransitionInFlight = false;
    }
  }

  Future<void> _onEnterForeground() async {
    if (!_appInBackground &&
        _activeIosTaskKeys.isEmpty &&
        _backgroundPulseTimer == null) {
      return;
    }
    _appInBackground = false;
    _stopBackgroundPulseLoop();
    if (Platform.isIOS) {
      await _endAllIosBackgroundTasks();
    }
    if (_bridge.isWalletOpenForBackgroundSync) {
      await _bridge.recoverWalletSessionAfterForeground();
      unawaited(_bridge.pulseBackgroundWalletSync());
    }
  }

  /// Dart [Timer.periodic] heartbeats pause when the OS suspends the isolate; pulse
  /// explicitly while backgrounded (iOS bg task window or Android paused state).
  void _startBackgroundPulseLoop() {
    _stopBackgroundPulseLoop();
    if (!_bridge.isWalletOpenForBackgroundSync) {
      return;
    }
    _backgroundPulseTimer =
        Timer.periodic(_kBackgroundPulseInterval, (_) {
      unawaited(_bridge.pulseBackgroundWalletSync());
    });
    unawaited(_bridge.pulseBackgroundWalletSync());
  }

  void _stopBackgroundPulseLoop() {
    _backgroundPulseTimer?.cancel();
    _backgroundPulseTimer = null;
  }

  /// Called from native when a `UIBackgroundTask` is about to expire (~30–180 s).
  Future<void> handleBackgroundTaskExpiring() async {
    if (!Platform.isIOS) {
      return;
    }
    if (!_appInBackground || !_bridge.isWalletOpenForBackgroundSync) {
      await _endAllIosBackgroundTasks();
      return;
    }
    debugPrint('[MobileBackgroundWalletSync] iOS bg task expiring — persist + chain');
    await _bridge.persistWalletBeforeSuspend(reason: 'task_expiring');
    await _endAllIosBackgroundTasks();
    await _bridge.pulseBackgroundWalletSync();
    await _beginIosBackgroundTask();
    if (_backgroundPulseTimer == null) {
      _startBackgroundPulseLoop();
    }
    await IosBackgroundSync.scheduleProcessingSync();
  }

  /// Called from native `BGProcessingTask` when iOS wakes the app for wallet sync.
  Future<void> performBackgroundPulse() async {
    if (!Platform.isIOS || !_bridge.isWalletOpenForBackgroundSync) {
      return;
    }
    debugPrint('[MobileBackgroundWalletSync] BGProcessingTask wallet pulse');
    await _bridge.persistWalletBeforeSuspend(reason: 'bg_processing');
    await _bridge.pulseBackgroundWalletSync();
    if (_appInBackground) {
      await _beginIosBackgroundTask();
    }
  }

  Future<void> _beginIosBackgroundTask() async {
    if (!Platform.isIOS) {
      return;
    }
    final int? key = await IosBackgroundSync.beginBackgroundSync();
    if (key != null) {
      _activeIosTaskKeys.add(key);
    }
  }

  Future<void> _endAllIosBackgroundTasks() async {
    if (!Platform.isIOS || _activeIosTaskKeys.isEmpty) {
      return;
    }
    final List<int> keys = _activeIosTaskKeys.toList();
    _activeIosTaskKeys.clear();
    for (final int key in keys) {
      await IosBackgroundSync.endBackgroundSync(key);
    }
  }
}
