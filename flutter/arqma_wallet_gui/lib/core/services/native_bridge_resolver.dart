import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../desktop/flutter_env_guard.dart';
import 'desktop_native_bridge.dart';
import 'native_bridge.dart';

/// Prefer the platform **MethodChannel** embedder (`com.arqma.wallet/native`) when it
/// responds to [kArqmaNativePingMethod]; otherwise use [DesktopNativeBridge] on desktop OS.
///
/// Set `ARQMA_FLUTTER_USE_STUB=1` to force [StubNativeBridge] for UI-only work (debug/profile only).
Future<NativeBridge> resolveAppNativeBridge() async {
  if (kIsWeb) {
    return StubNativeBridge();
  }
  if (flutterDebugEnvFlag('ARQMA_FLUTTER_USE_STUB')) {
    return StubNativeBridge();
  }
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    if (await _methodChannelNativeAvailable()) {
      final MethodChannelNativeBridge bridge = MethodChannelNativeBridge();
      await bridge.start();
      return bridge;
    }
    return DesktopNativeBridge();
  }
  return StubNativeBridge();
}

/// Channel method the macOS/Linux/Windows embedder should implement to take over from Dart I/O.
const String kArqmaNativePingMethod = 'native_ping';

Future<bool> _methodChannelNativeAvailable() async {
  const MethodChannel channel = MethodChannel('com.arqma.wallet/native');
  try {
    final Object? r =
        await channel.invokeMethod<Object>(kArqmaNativePingMethod);
    return r == true || r == 'ok' || r == 1;
  } on MissingPluginException {
    return false;
  } catch (e) {
    debugPrint('[NativeBridgeResolver] $kArqmaNativePingMethod: $e');
    return false;
  }
}
