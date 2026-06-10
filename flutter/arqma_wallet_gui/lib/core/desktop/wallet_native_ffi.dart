import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'flutter_env_guard.dart';

/// Optional absolute path to `libarqma_wallet_flutter_ffi.{dylib,so}` or `arqma_wallet_flutter_ffi.dll`.
const String kArqmaFlutterWalletFfiEnv = 'ARQMA_FLUTTER_WALLET_FFI';

typedef _ConfigureNative = Int32 Function(
    Pointer<Utf8> walletDir, Pointer<Utf8> daemonAddress, Int32 network);
typedef _ConfigureDart = int Function(
    Pointer<Utf8> walletDir, Pointer<Utf8> daemonAddress, int network);

typedef _CallJsonNative = Int32 Function(
  Pointer<Utf8> method,
  Pointer<Utf8> paramsJson,
  Pointer<Pointer<Utf8>> outJson,
);
typedef _CallJsonDart = int Function(
  Pointer<Utf8> method,
  Pointer<Utf8> paramsJson,
  Pointer<Pointer<Utf8>> outJson,
);

typedef _ResetNative = Int32 Function();
typedef _ResetDart = int Function();

typedef _StringFreeNative = Void Function(Pointer<Utf8> p);
typedef _StringFreeDart = void Function(Pointer<Utf8> p);

typedef _SetDefaultDllDirectoriesNative = Int32 Function(Uint32 DirectoryFlags);
typedef _SetDefaultDllDirectoriesDart = int Function(int DirectoryFlags);

/// In-process wallet2 via `rust/arqma-wallet-flutter-ffi` (same `Wallet2ApiClient` as Tauri native mode).
final class WalletNativeFfi {
  WalletNativeFfi._(DynamicLibrary lib)
      : _dylib = lib,
        _configure = lib.lookupFunction<_ConfigureNative, _ConfigureDart>(
            'arqma_wallet_ffi_configure'),
        _callJson = lib.lookupFunction<_CallJsonNative, _CallJsonDart>(
            'arqma_wallet_ffi_call_json'),
        _reset = lib
            .lookupFunction<_ResetNative, _ResetDart>('arqma_wallet_ffi_reset'),
        _stringFree = lib.lookupFunction<_StringFreeNative, _StringFreeDart>(
            'arqma_wallet_ffi_string_free');

  final DynamicLibrary _dylib; // ignore: unused_field — keeps the dylib loaded.
  final _ConfigureDart _configure;
  final _CallJsonDart _callJson;
  final _ResetDart _reset;
  final _StringFreeDart _stringFree;

  /// `network`: 0 mainnet, 1 testnet, 2 stagenet (matches Rust `arqma_wallet_ffi_configure`).
  int configure(String walletDir, String daemonAddress, int network) {
    final Pointer<Utf8> wd = walletDir.toNativeUtf8();
    final Pointer<Utf8> da = daemonAddress.toNativeUtf8();
    try {
      return _configure(wd, da, network);
    } finally {
      malloc.free(wd);
      malloc.free(da);
    }
  }

  void reset() {
    _reset();
  }

  Future<Map<String, dynamic>?> callJsonRpc(
      String method, Object params) async {
    final Pointer<Utf8> m = method.toNativeUtf8();
    final String paramsStr = jsonEncode(params);
    final Pointer<Utf8> pj = paramsStr.toNativeUtf8();
    final Pointer<Pointer<Utf8>> out = malloc<Pointer<Utf8>>();
    out.value = nullptr;
    try {
      final int code = _callJson(m, pj, out);
      if (code != 0) {
        debugPrint('[WalletNativeFfi] call_json code=$code method=$method');
        return null;
      }
      final Pointer<Utf8> raw = out.value;
      if (raw == nullptr) {
        return null;
      }
      try {
        final String s = raw.toDartString();
        final Object? decoded = jsonDecode(s);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        return null;
      } finally {
        _stringFree(raw);
      }
    } finally {
      malloc.free(m);
      malloc.free(pj);
      malloc.free(out);
    }
  }

  /// Last load error (path + exception) for wallet startup diagnostics / UI.
  static String lastLoadFailureDetail = '';

  static bool _windowsSearchPathPrepared = false;

  /// Call once from `main()` on Windows before wallet FFI (incl. worker isolates).
  static void prepareWindowsDllSearchPath() {
    if (kIsWeb || !Platform.isWindows || _windowsSearchPathPrepared) {
      return;
    }
    _windowsSearchPathPrepared = true;
    try {
      final String exeDir = File(Platform.resolvedExecutable).parent.path;
      _configureWindowsDllSearch(exeDir);
      _preloadWindowsDllsFrom(exeDir);
      final String libDir = '$exeDir${Platform.pathSeparator}lib';
      if (Directory(libDir).existsSync()) {
        _preloadWindowsDllsFrom(libDir);
      }
    } catch (e, st) {
      debugPrint('[WalletNativeFfi] prepareWindowsDllSearchPath: $e\n$st');
    }
  }

  static void _configureWindowsDllSearch(String exeDir) {
    final DynamicLibrary k32 = DynamicLibrary.open('kernel32.dll');
    try {
      final _SetDefaultDllDirectoriesDart setDefault = k32.lookupFunction<
          _SetDefaultDllDirectoriesNative, _SetDefaultDllDirectoriesDart>(
        'SetDefaultDllDirectories',
      );
      // Application dir + System32 / WinSxS (avoid SetDllDirectory — breaks some Setup installs).
      const int loadDefaultDirs = 0x00001000;
      const int loadAppDir = 0x00002000;
      if (setDefault(loadDefaultDirs | loadAppDir) == 0) {
        debugPrint('[WalletNativeFfi] SetDefaultDllDirectories failed');
      }
    } catch (e) {
      debugPrint('[WalletNativeFfi] SetDefaultDllDirectories unavailable: $e');
    }
    _addWindowsDllDirectory(exeDir);
    final String libDir = '$exeDir${Platform.pathSeparator}lib';
    if (Directory(libDir).existsSync()) {
      _addWindowsDllDirectory(libDir);
    }
  }

  static void _addWindowsDllDirectory(String dir) {
    try {
      final DynamicLibrary k32 = DynamicLibrary.open('kernel32.dll');
      final int Function(Pointer<Utf16>) addDir = k32.lookupFunction<
          IntPtr Function(Pointer<Utf16>),
          int Function(Pointer<Utf16>)>('AddDllDirectory');
      final Pointer<Utf16> dirW = dir.toNativeUtf16();
      try {
        final int cookie = addDir(dirW);
        if (cookie == 0) {
          debugPrint('[WalletNativeFfi] AddDllDirectory failed for: $dir');
        }
      } finally {
        malloc.free(dirW);
      }
    } catch (e) {
      debugPrint('[WalletNativeFfi] AddDllDirectory unavailable: $e');
    }
  }

  /// MinGW-built `arqma_wallet_flutter_ffi.dll` links many DLLs dynamically; Dart
  /// `DynamicLibrary.open` often fails with **Win32 error 126/1114** when a dependency is missing
  /// or loaded in the wrong order (ICU before Boost, runtime before wallet stack).
  static void _preloadWindowsDllsFrom(String baseDir) {
    const List<String> runtime = <String>[
      'libgcc_s_seh-1.dll',
      'libstdc++-6.dll',
      'libwinpthread-1.dll',
    ];
    const List<String> tier1Prefixes = <String>[
      'libicu',
      'libcrypto',
      'libssl',
      'libsodium',
      'libunbound',
      'libzmq',
      'libhidapi',
      'libiconv',
      'libncurses',
      'libtermcap',
      'libhistory',
      'libreadline',
      'libintl',
      'liblmdb',
      'libevent',
      'libcares',
      'libexpat',
      'libsqlite3',
      'libgmp',
      'libnghttp',
      'zlib1.dll',
      'libzstd',
      'libbz2',
      'liblzma',
      'libxml2',
      'libffi',
      'libssp',
      'liblz4',
      'libbrotli',
      'libdeflate',
      'libatomic',
      'libldns',
    ];
    const List<String> skipNames = <String>[
      'flutter_windows.dll',
      'arqma_wallet_flutter_ffi.dll',
    ];

    final Directory dir = Directory(baseDir);
    if (!dir.existsSync()) {
      return;
    }
    final Map<String, String> byLower = <String, String>{};
    for (final FileSystemEntity ent in dir.listSync()) {
      if (ent is! File) {
        continue;
      }
      final String name = ent.uri.pathSegments.last;
      byLower[name.toLowerCase()] = ent.path;
    }

    void preloadName(String name, {bool critical = false}) {
      final String? path = byLower[name.toLowerCase()];
      if (path == null) {
        if (critical) {
          debugPrint('[WalletNativeFfi] missing critical preload: $name in $baseDir');
        }
        return;
      }
      _tryPreloadDllFile(path, critical: critical);
    }

    for (final String n in runtime) {
      preloadName(n, critical: true);
    }

    final List<String> tier1 = byLower.keys
        .where((String n) =>
            tier1Prefixes.any((String p) => n.toLowerCase().startsWith(p)))
        .toList()
      ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final String n in tier1) {
      preloadName(n);
    }

    final List<String> boost = byLower.keys
        .where((String n) => n.toLowerCase().startsWith('libboost_'))
        .toList()
      ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final String n in boost) {
      if (n.toLowerCase().contains('python') ||
          n.toLowerCase().contains('numpy')) {
        continue;
      }
      preloadName(n);
    }

    final List<String> rest = byLower.keys
        .where((String n) =>
            !runtime.contains(n) &&
            !tier1.contains(n) &&
            !n.toLowerCase().startsWith('libboost_') &&
            !skipNames.contains(n.toLowerCase()))
        .toList()
      ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final String n in rest) {
      preloadName(n);
    }
  }

  static void _tryPreloadDllFile(String path, {bool critical = false}) {
    if (!File(path).existsSync()) {
      return;
    }
    try {
      DynamicLibrary.open(path);
    } catch (e) {
      final String msg = '[WalletNativeFfi] preload skip $path: $e';
      if (critical) {
        debugPrint('::warning::$msg');
      } else {
        debugPrint(msg);
      }
    }
  }

  static WalletNativeFfi? tryLoad() {
    if (kIsWeb) {
      return null;
    }
    lastLoadFailureDetail = '';
    final List<String> tried = <String>[];
    if (Platform.isWindows) {
      prepareWindowsDllSearchPath();
    }
    final List<String> errors = <String>[];
    for (final String path in _candidateLibraryPaths()) {
      if (path.isEmpty) {
        continue;
      }
      tried.add(path);
      try {
        final DynamicLibrary lib = DynamicLibrary.open(path);
        return WalletNativeFfi._(lib);
      } catch (e) {
        final String line = '$path: $e';
        errors.add(line);
        lastLoadFailureDetail = line;
        debugPrint('[WalletNativeFfi] skip open "$path": $e');
      }
    }
    if (errors.isNotEmpty) {
      lastLoadFailureDetail = errors.join(' | ');
    } else if (tried.isNotEmpty) {
      lastLoadFailureDetail = 'tried: ${tried.join(", ")}';
    }
    return null;
  }

  static List<String> _candidateLibraryPaths() {
    final String? fromEnv = flutterDebugEnvPath(kArqmaFlutterWalletFfiEnv);
    final List<String> out = <String>[];
    if (fromEnv != null && fromEnv.isNotEmpty) {
      out.add(fromEnv);
    }
    final String exe = Platform.resolvedExecutable;
    final String dir = File(exe).parent.path;
    if (Platform.isMacOS) {
      out.add('$dir/../Frameworks/libarqma_wallet_flutter_ffi.dylib');
      out.add('$dir/libarqma_wallet_flutter_ffi.dylib');
    } else if (Platform.isLinux) {
      out.add('$dir/lib/libarqma_wallet_flutter_ffi.so');
      out.add('$dir/libarqma_wallet_flutter_ffi.so');
    } else if (Platform.isWindows) {
      out.add('$dir${Platform.pathSeparator}arqma_wallet_flutter_ffi.dll');
      out.add(
          '$dir${Platform.pathSeparator}lib${Platform.pathSeparator}arqma_wallet_flutter_ffi.dll');
    }
    return out;
  }
}

int networkCodeForNetType(String? net) {
  switch (net) {
    case 'testnet':
      return 1;
    case 'stagenet':
      return 2;
    default:
      return 0;
  }
}
