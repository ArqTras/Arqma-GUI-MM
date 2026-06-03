import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../desktop/flutter_env_guard.dart';
import 'mobile_native_bridge.dart';
import 'native_bridge.dart';

/// iOS/Android use [MobileNativeBridge] (remote nodes + in-process wallet FFI).
/// Set `ARQMA_FLUTTER_USE_STUB=1` to force [StubNativeBridge] for UI-only work (debug/profile only).
Future<NativeBridge> resolveAppNativeBridge() async {
  if (kIsWeb) {
    return StubNativeBridge();
  }
  if (flutterDebugEnvFlag('ARQMA_FLUTTER_USE_STUB')) {
    return StubNativeBridge();
  }
  if (Platform.isIOS || Platform.isAndroid) {
    final MobileNativeBridge bridge = MobileNativeBridge();
    await bridge.start();
    return bridge;
  }
  return StubNativeBridge(navigateWalletSelectAfterInit: false);
}
