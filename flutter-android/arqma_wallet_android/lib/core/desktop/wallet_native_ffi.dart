import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'bridge_log_redact.dart';
import 'flutter_env_guard.dart';

/// Optional absolute path to `libarqma_wallet_flutter_ffi.{dylib,so}` or `arqma_wallet_flutter_ffi.dll`.
const String kArqmaFlutterWalletFfiEnv = 'ARQMA_FLUTTER_WALLET_FFI';

/// Set to `subprocess` to use the legacy `arqma-wallet-rpc` child + HTTP instead of in-process FFI.
const String kArqmaFlutterWalletRpcModeEnv = 'ARQMA_FLUTTER_WALLET_RPC_MODE';

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

typedef _SetDllDirectoryWNative = Int32 Function(Pointer<Utf16> lpPathName);
typedef _SetDllDirectoryWDart = int Function(Pointer<Utf16> lpPathName);

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

  /// MinGW-built `arqma_wallet_flutter_ffi.dll` links these DLLs dynamically; Dart `DynamicLibrary`
  /// on `ffi.dll` often fails with **Win32 error 126** (“module not found”) when a *dependency*
  /// is missing — preload by **absolute path** fixes that reliably.
  ///
  /// Bundles place MinGW runtime DLLs next to `Arqma-Wallet.exe` (and may still use legacy `lib/`).
  static void _preloadWindowsDllsFrom(String baseDir) {
    const List<String> names = <String>[
      'libgcc_s_seh-1.dll',
      'libstdc++-6.dll',
      'libwinpthread-1.dll',
    ];
    for (final String n in names) {
      final String p = '$baseDir${Platform.pathSeparator}$n';
      if (!File(p).existsSync()) {
        debugPrint('[WalletNativeFfi] preload skip (missing file): $p');
        continue;
      }
      try {
        DynamicLibrary.open(p);
        debugPrint('[WalletNativeFfi] preloaded dependency: $p');
      } catch (e, st) {
        debugPrint('[WalletNativeFfi] preload failed $p: $e\n$st');
      }
    }
  }

  static WalletNativeFfi? tryLoad() {
    if (kIsWeb) {
      return null;
    }
    lastLoadFailureDetail = '';
    final List<String> tried = <String>[];
    bool windowsDllDirSet = false;
    if (Platform.isWindows) {
      try {
        final String exeDir = File(Platform.resolvedExecutable).parent.path;
        final DynamicLibrary k32 = DynamicLibrary.open('kernel32.dll');
        final _SetDllDirectoryWDart setDll = k32.lookupFunction<
            _SetDllDirectoryWNative,
            _SetDllDirectoryWDart>('SetDllDirectoryW');
        final Pointer<Utf16> dirW = exeDir.toNativeUtf16();
        try {
          if (setDll(dirW) != 0) {
            windowsDllDirSet = true;
          }
        } finally {
          malloc.free(dirW);
        }
        _preloadWindowsDllsFrom(exeDir);
        // Legacy layout: deps only under lib/
        final String libDir = '$exeDir${Platform.pathSeparator}lib';
        if (Directory(libDir).existsSync()) {
          _preloadWindowsDllsFrom(libDir);
        }
      } catch (e) {
        debugPrint('[WalletNativeFfi] SetDllDirectoryW / preload skipped: $e');
      }
    }
    try {
      final List<String> errors = <String>[];
      for (final String path in _candidateLibraryPaths()) {
        if (path.isEmpty) {
          continue;
        }
        if (Platform.isIOS &&
            !path.startsWith('@') &&
            !File(path).existsSync()) {
          final String line = '$path: file not found in app bundle';
          errors.add(line);
          lastLoadFailureDetail = line;
          debugPrint('[WalletNativeFfi] skip (missing): $path');
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
    } finally {
      if (Platform.isWindows && windowsDllDirSet) {
        try {
          final DynamicLibrary k32 = DynamicLibrary.open('kernel32.dll');
          final _SetDllDirectoryWDart setDll = k32.lookupFunction<
              _SetDllDirectoryWNative,
              _SetDllDirectoryWDart>('SetDllDirectoryW');
          setDll(nullptr);
        } catch (_) {}
      }
    }
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
    } else if (Platform.isIOS) {
      // App Store build embeds FFI as a framework (not a loose dylib in Frameworks/).
      out.add(
          '$dir/Frameworks/libarqma_wallet_flutter_ffi.framework/libarqma_wallet_flutter_ffi');
      out.add('$dir/Frameworks/libarqma_wallet_flutter_ffi.dylib');
      out.add('libarqma_wallet_flutter_ffi.framework/libarqma_wallet_flutter_ffi');
      out.add('libarqma_wallet_flutter_ffi.dylib');
    } else if (Platform.isAndroid) {
      // Packaged under android/app/src/main/jniLibs/<abi>/ by tool/copy_android_wallet_ffi.*
      out.add('libarqma_wallet_flutter_ffi.so');
      final String jni = '$dir${Platform.pathSeparator}lib';
      if (Directory(jni).existsSync()) {
        for (final String abi in <String>['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
          final String p =
              '$jni${Platform.pathSeparator}$abi${Platform.pathSeparator}libarqma_wallet_flutter_ffi.so';
          if (File(p).existsSync()) {
            out.add(p);
          }
        }
      }
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
