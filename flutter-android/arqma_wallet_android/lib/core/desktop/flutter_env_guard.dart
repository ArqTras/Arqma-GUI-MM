import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// True only in debug/profile when [name]=1. Release builds ignore env overrides.
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
