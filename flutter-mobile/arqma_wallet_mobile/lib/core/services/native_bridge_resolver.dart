import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'mobile_native_bridge.dart';
import 'native_bridge.dart';

/// iOS/Android use [MobileNativeBridge] (remote nodes + in-process wallet FFI).
/// `ARQMA_FLUTTER_USE_STUB=1` forces [StubNativeBridge] for UI-only work.
Future<NativeBridge> resolveAppNativeBridge() async {
  if (kIsWeb) {
    return StubNativeBridge();
  }
  if (Platform.environment['ARQMA_FLUTTER_USE_STUB'] == '1') {
    return StubNativeBridge();
  }
  if (Platform.isIOS || Platform.isAndroid) {
    final MobileNativeBridge bridge = MobileNativeBridge();
    await bridge.start();
    return bridge;
  }
  return StubNativeBridge(navigateWalletSelectAfterInit: false);
}
