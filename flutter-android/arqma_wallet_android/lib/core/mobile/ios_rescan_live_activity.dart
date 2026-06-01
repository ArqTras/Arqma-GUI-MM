/// No-op stub for the legacy Android app tree.
///
/// Live Activity is iOS-only; see
/// `flutter-mobile/arqma_wallet_mobile/lib/core/mobile/ios_rescan_live_activity.dart`.
class IosRescanLiveActivity {
  IosRescanLiveActivity._();

  static Future<void> init() async {}

  static Future<void> startOrUpdate({
    required int current,
    required int target,
    String subtitle = 'Syncing wallet',
  }) async {}

  static Future<void> end() async {}
}
