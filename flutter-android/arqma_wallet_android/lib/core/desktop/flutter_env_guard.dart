import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// True only in debug/profile when [name]=1. Release builds ignore env overrides.
///
/// Gated vars include: `ARQMA_FLUTTER_USE_STUB`, `ARQMA_FLUTTER_WALLET_FFI`,
/// `ARQMA_FLUTTER_FFI_NO_ISOLATE`, `ARQMA_FLUTTER_NO_WALLET_RPC`,
/// `ARQMA_FLUTTER_DEBUG_WALLET`, `ARQMA_FLUTTER_WALLET_RPC_MODE`, `ARQMA_DAEMON`,
/// `ARQMA_WALLET_RPC`, `ARQMA_BUILD_DIR`, `ARQMA_INSTALL_PREFIX`.
bool flutterDebugEnvFlag(String name) {
  if (kReleaseMode) {
    return false;
  }
  return Platform.environment[name] == '1';
}

/// Non-empty env override allowed in debug/profile only (e.g. custom FFI path).
String? flutterDebugEnvPath(String name) {
  if (kReleaseMode) {
    return null;
  }
  final String? v = Platform.environment[name]?.trim();
  if (v == null || v.isEmpty) {
    return null;
  }
  return v;
}

/// Raw env value in debug/profile only (e.g. `ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess`).
String? flutterDebugEnvValue(String name) => flutterDebugEnvPath(name);
