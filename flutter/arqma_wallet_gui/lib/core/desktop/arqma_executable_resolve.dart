import 'dart:io';

import 'package:flutter/foundation.dart';

/// Same resolution order as [arqma_wallet_rpc::upstream_paths::resolve_arqma_executable]
/// plus bundle-style paths from [native_bin::bundled_exe_candidates] (without Tauri `resource_dir`).
enum ArqmaExecutableKind {
  walletRpc,
  daemon,
}

String _exeWin(ArqmaExecutableKind k) => k == ArqmaExecutableKind.daemon ? 'arqmad.exe' : 'arqma-wallet-rpc.exe';

String _exeUnix(ArqmaExecutableKind k) => k == ArqmaExecutableKind.daemon ? 'arqmad' : 'arqma-wallet-rpc';

String _pickExeName(ArqmaExecutableKind k) => Platform.isWindows ? _exeWin(k) : _exeUnix(k);

String? _directEnvPath(ArqmaExecutableKind k) {
  final String? v = k == ArqmaExecutableKind.daemon
      ? Platform.environment['ARQMA_DAEMON']
      : Platform.environment['ARQMA_WALLET_RPC'];
  if (v == null || v.trim().isEmpty) {
    return null;
  }
  final String p = v.trim();
  return File(p).existsSync() ? p : null;
}

/// If [root] already ends with `bin`, use it; else `<root>/bin` (same as Rust `bin_subdir`).
String _binSubdir(String root) {
  final String t = root.trim();
  if (t.isEmpty) {
    return t;
  }
  final String sep = Platform.pathSeparator;
  final List<String> parts = t.split(sep).where((String s) => s.isNotEmpty).toList();
  if (parts.isNotEmpty && parts.last.toLowerCase() == 'bin') {
    return t;
  }
  return '$t${sep}bin';
}

String? _exeInBinRoot(String root, ArqmaExecutableKind k) {
  final String binDir = _binSubdir(root);
  if (binDir.isEmpty) {
    return null;
  }
  final String name = _pickExeName(k);
  final String p = '$binDir${Platform.pathSeparator}$name';
  return File(p).existsSync() ? p : null;
}

String? _findInPath(ArqmaExecutableKind k) {
  final String name = _pickExeName(k);
  final String? pathVar = Platform.environment['PATH'];
  if (pathVar == null || pathVar.isEmpty) {
    return null;
  }
  final String sep = Platform.isWindows ? ';' : ':';
  for (final String dir in pathVar.split(sep)) {
    final String d = dir.trim();
    if (d.isEmpty) {
      continue;
    }
    final String p = '$d${Platform.pathSeparator}$name';
    if (File(p).existsSync()) {
      return p;
    }
  }
  return null;
}

/// Extra search paths aligned with `native_bin::bundled_exe_candidates` (no Tauri `resource_dir`).
List<String> _bundledStyleCandidates(ArqmaExecutableKind k) {
  final String name = _pickExeName(k);
  final String sep = Platform.pathSeparator;
  final List<String> out = <String>[];

  void addIf(String path) {
    if (path.isNotEmpty && File(path).existsSync()) {
      out.add(path);
    }
  }

  // `env!("CARGO_MANIFEST_DIR")/bin` — fixed repo layout from repo root / cwd walk.
  Directory cur = Directory.current;
  for (int i = 0; i < 12; i++) {
    addIf(<String>[cur.path, 'rust', 'tauri-app', 'src-tauri', 'bin', name].join(sep));
    addIf(<String>[cur.path, 'src-tauri', 'bin', name].join(sep));
    if (cur.parent.path == cur.path) {
      break;
    }
    cur = cur.parent;
  }

  addIf(<String>['bin', name].join(sep));
  addIf(<String>['binaries', name].join(sep));

  final String exe = Platform.resolvedExecutable;
  final String exeDir = File(exe).parent.path;
  addIf('$exeDir${sep}bin$sep$name');
  addIf('$exeDir$sep$name');
  final String parent = File(exe).parent.parent.path;
  addIf('$parent${sep}bin$sep$name');

  return out;
}

/// Resolve `arqmad` or `arqma-wallet-rpc` like the Tauri shell (`upstream_paths` + bundle candidates).
String? resolveArqmaExecutable(ArqmaExecutableKind kind) {
  final String? direct = _directEnvPath(kind);
  if (direct != null) {
    return direct;
  }
  final String? build = Platform.environment['ARQMA_BUILD_DIR'];
  if (build != null && build.isNotEmpty) {
    final String? p = _exeInBinRoot(build, kind);
    if (p != null) {
      return p;
    }
  }
  final String? prefix = Platform.environment['ARQMA_INSTALL_PREFIX'];
  if (prefix != null && prefix.isNotEmpty) {
    final String? p = _exeInBinRoot(prefix, kind);
    if (p != null) {
      return p;
    }
  }
  final String? pathHit = _findInPath(kind);
  if (pathHit != null) {
    return pathHit;
  }
  for (final String c in _bundledStyleCandidates(kind)) {
    if (File(c).existsSync()) {
      return c;
    }
  }
  debugPrint('[ArqmaExe] not found: ${kind.name} (${_pickExeName(kind)})');
  return null;
}
