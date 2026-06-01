import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';

/// iOS Live Activity / Dynamic Island progress during full blockchain rescan.
class IosRescanLiveActivity {
  IosRescanLiveActivity._();

  static const String appGroupId = 'group.com.arqma.arqmaWalletMobile';

  static const String activityId = 'arqma_wallet_rescan';

  static LiveActivities? _plugin;
  static bool _initAttempted = false;
  static bool _initOk = false;

  static Future<void> init() async {
    if (!Platform.isIOS || _initAttempted) {
      return;
    }
    _initAttempted = true;
    try {
      final LiveActivities plugin = LiveActivities();
      await plugin.init(appGroupId: appGroupId);
      _plugin = plugin;
      _initOk = true;
    } catch (e, st) {
      debugPrint('[IosRescanLiveActivity] init: $e\n$st');
      _initOk = false;
    }
  }

  static Future<bool> get _canUse async {
    if (!Platform.isIOS || !_initOk || _plugin == null) {
      return false;
    }
    try {
      if (!await _plugin!.areActivitiesSupported()) {
        return false;
      }
      return await _plugin!.areActivitiesEnabled();
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> _payload({
    required int current,
    required int target,
    required double pct,
  }) {
    final int pctInt = pct.clamp(0, 100).round();
    return <String, dynamic>{
      'title': 'Arqma Wallet',
      'subtitle': 'Blockchain rescan',
      'current': current,
      'target': target,
      'pct': pctInt,
    };
  }

  static Future<void> startOrUpdate({
    required int current,
    required int target,
  }) async {
    if (!await _canUse) {
      return;
    }
    final LiveActivities plugin = _plugin!;
    final double pct =
        target > 0 ? (100.0 * current / target).clamp(0, 100) : 0.0;
    final Map<String, dynamic> data =
        _payload(current: current, target: target, pct: pct);
    try {
      await plugin.createOrUpdateActivity(
        activityId,
        data,
        iOSEnableRemoteUpdates: false,
      );
    } catch (e, st) {
      debugPrint('[IosRescanLiveActivity] startOrUpdate: $e\n$st');
    }
  }

  static Future<void> end() async {
    if (!Platform.isIOS || !_initOk || _plugin == null) {
      return;
    }
    try {
      await _plugin!.endActivity(activityId);
    } catch (e, st) {
      debugPrint('[IosRescanLiveActivity] end: $e\n$st');
    }
  }
}
