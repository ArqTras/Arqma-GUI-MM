import 'dart:io';

import 'package:flutter/foundation.dart';

import 'flutter_env_guard.dart';

/// Same resolution order as upstream `resolve_arqma_executable` plus bundle `bin/` paths.
enum ArqmaExecutableKind {
  walletRpc,
  daemon,
  flutterSoloPool,
}

String _exeWin(ArqmaExecutableKind k) {
  return switch (k) {
    ArqmaExecutableKind.daemon => 'arqmad.exe',
    ArqmaExecutableKind.flutterSoloPool => 'arqma_flutter_solo_pool.exe',
    ArqmaExecutableKind.walletRpc => 'arqma-wallet-rpc.exe',
  };
}

String _exeUnix(ArqmaExecutableKind k) {
  return switch (k) {
    ArqmaExecutableKind.daemon => 'arqmad',
    ArqmaExecutableKind.flutterSoloPool => 'arqma_flutter_solo_pool',
    ArqmaExecutableKind.walletRpc => 'arqma-wallet-rpc',
  };
}

String _pickExeName(ArqmaExecutableKind k) =>
    Platform.isWindows ? _exeWin(k) : _exeUnix(k);

String? _directEnvPath(ArqmaExecutableKind k) {
  final String? v = switch (k) {
    ArqmaExecutableKind.daemon => flutterDebugEnvPath('ARQMA_DAEMON'),
    ArqmaExecutableKind.flutterSoloPool =>
      flutterDebugEnvPath('ARQMA_FLUTTER_SOLO_POOL'),
    ArqmaExecutableKind.walletRpc => flutterDebugEnvPath('ARQMA_WALLET_RPC'),
  };
  if (v == null || v.trim().isEmpty) {
    return null;
  }
  final String p = v.trim();
  return File(p).existsSync() ? p : null;
}

/// App bundle: `Resources/bin/<name>` (macOS) or `<exe_dir>/bin/<name>`.
String? _bundleStyleExecutable(ArqmaExecutableKind kind) {
  final String name = _pickExeName(kind);
  final String sep = Platform.pathSeparator;
  try {
    final String exePath = Platform.resolvedExecutable;
    final Directory exeParent = File(exePath).parent;
    if (Platform.isMacOS && exeParent.path.endsWith('$sep' 'MacOS')) {
      final String resourcesBin = '${exeParent.parent.path}$sep'
          'Resources$sep'
          'bin$sep$name';
      if (File(resourcesBin).existsSync()) {
        return resourcesBin;
      }
    }
    final String beside = '${exeParent.path}$sep'
        'bin$sep$name';
    if (File(beside).existsSync()) {
      return beside;
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// Walk parents from [Platform.resolvedExecutable] to find `build/flutter-desktop-bin/`.
String? _exeInFlutterDesktopBinNearResolvedExecutable(ArqmaExecutableKind kind) {
  final String sep = Platform.pathSeparator;
  final String name = _pickExeName(kind);
  try {
    Directory dir = File(Platform.resolvedExecutable).parent;
    for (int i = 0; i < 18; i++) {
      final String p = <String>[
        dir.path,
        'build',
        'flutter-desktop-bin',
        name,
      ].join(sep);
      if (File(p).existsSync()) {
        return p;
      }
      final Directory parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
  } catch (_) {
    return null;
  }
  return null;
}

String _binSubdir(String root) {
  final String t = root.trim();
  if (t.isEmpty) {
    return t;
  }
  final String sep = Platform.pathSeparator;
  final List<String> parts =
      t.split(sep).where((String s) => s.isNotEmpty).toList();
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

List<String> _bundledStyleCandidates(ArqmaExecutableKind k) {
  final String name = _pickExeName(k);
  final String sep = Platform.pathSeparator;
  final List<String> out = <String>[];

  void addIf(String path) {
    if (path.isNotEmpty && File(path).existsSync()) {
      out.add(path);
    }
  }

  void addSoloPoolRustTargetIf(String root) {
    if (k != ArqmaExecutableKind.flutterSoloPool) {
      return;
    }
    addIf(<String>[root, 'rust', 'target', 'debug', name].join(sep));
    addIf(<String>[root, 'rust', 'target', 'release', name].join(sep));
  }

  Directory cur = Directory.current;
  for (int i = 0; i < 12; i++) {
    addIf(<String>[cur.path, 'build', 'flutter-desktop-bin', name].join(sep));
    addIf(<String>[cur.path, 'bin', name].join(sep));
    addSoloPoolRustTargetIf(cur.path);
    if (cur.parent.path == cur.path) {
      break;
    }
    cur = cur.parent;
  }

  final String exe = Platform.resolvedExecutable;
  final String exeDir = File(exe).parent.path;
  addIf('$exeDir${sep}bin$sep$name');
  addIf('$exeDir$sep$name');
  final String parent = File(exe).parent.parent.path;
  addIf('$parent${sep}bin$sep$name');

  return out;
}

/// Resolve `arqmad`, solo pool sidecar, or legacy wallet-rpc binary.
String? resolveArqmaExecutable(ArqmaExecutableKind kind) {
  final String? direct = _directEnvPath(kind);
  if (direct != null) {
    return direct;
  }
  final String? bundled = _bundleStyleExecutable(kind);
  if (bundled != null) {
    return bundled;
  }
  final String? nearCheckout = _exeInFlutterDesktopBinNearResolvedExecutable(kind);
  if (nearCheckout != null) {
    return nearCheckout;
  }
  final String? build = flutterDebugEnvPath('ARQMA_BUILD_DIR');
  if (build != null && build.isNotEmpty) {
    final String? p = _exeInBinRoot(build, kind);
    if (p != null) {
      return p;
    }
  }
  final String? prefix = flutterDebugEnvPath('ARQMA_INSTALL_PREFIX');
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
