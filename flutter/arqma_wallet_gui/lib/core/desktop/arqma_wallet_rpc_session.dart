import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'dart:math' show Random;

import 'package:flutter/foundation.dart';

import 'arqma_paths.dart';
import 'daemon_json_rpc.dart';
import 'wallet_ffi_isolate.dart';
import 'wallet_json_rpc.dart';
import 'wallet_native_ffi.dart';

/// After this many milliseconds in native FFI mode, a helper [Isolate] calls
/// [WalletNativeFfi.reset] so shutdown can proceed if `close_wallet` blocks the UI isolate.
const int kNativeWalletCloseWatchdogMs = 10000;

@pragma('vm:entry-point')
void _nativeWalletFfiResetWatchdogMain(int delayMs) {
  if (delayMs > 0) {
    sleep(Duration(milliseconds: delayMs));
  }
  try {
    WalletNativeFfi.tryLoad()?.reset();
  } catch (_) {}
}

/// Same random `rpc-login` shape as `wallet_process::generate_auth_triple` (160 bytes → 320 hex chars).
(String user, String pass, String salt) generateWalletRpcAuthTriple() {
  final Random rnd = Random.secure();
  final List<int> bytes = List<int>.generate(160, (_) => rnd.nextInt(256));
  final String s =
      bytes.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();
  return (s.substring(0, 64), s.substring(64, 128), s.substring(128, 192));
}

/// `wallet_process::wallet_daemon_addr` — `host:port` for `--daemon-address`.
String? walletDaemonAddress(Map<String, dynamic> configData) {
  final String net =
      (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final Object? daemons = configData['daemons'];
  if (daemons is! Map) {
    return null;
  }
  final Map<dynamic, dynamic> daemonsMap = Map<dynamic, dynamic>.from(daemons);
  final Object? entry = daemonsMap[net];
  if (entry is! Map) {
    return null;
  }
  final Map<String, dynamic> d = Map<String, dynamic>.from(entry);
  if (d['type'] == 'remote') {
    final String? h = d['remote_host'] as String?;
    final int? p = (d['remote_port'] as num?)?.toInt();
    if (h == null || p == null) {
      return null;
    }
    return '$h:$p';
  }
  final String h = d['rpc_bind_ip'] as String? ?? '127.0.0.1';
  final int p = (d['rpc_bind_port'] as num?)?.toInt() ?? 19994;
  return '$h:$p';
}

/// Wallet `--daemon-address`: use live local JSON-RPC when configured for local mode, else fall back
/// to `remote_host:remote_port` when local `arqmad` is not up yet (CLI users often point at remote).
Future<String?> resolveWalletDaemonAddress(
    Map<String, dynamic> configData) async {
  final String net =
      (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final Map<String, dynamic>? d =
      (configData['daemons'] as Map?)?[net] as Map<String, dynamic>?;
  if (d == null) {
    return walletDaemonAddress(configData);
  }
  final String typ = '${d['type'] ?? 'remote'}';
  if (typ == 'remote') {
    return walletDaemonAddress(configData);
  }
  final ({String host, int port})? localEp = daemonRpcHostPort(configData);
  if (localEp != null) {
    final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(
      localEp.host,
      localEp.port,
      connectTimeout: DaemonJsonRpc.probeConnectTimeout,
      requestTimeout: DaemonJsonRpc.probeRequestTimeout,
      quiet: true,
    );
    if (DaemonJsonRpc.getInfoPayload(r) != null) {
      return '${localEp.host}:${localEp.port}';
    }
  }
  final String? rh = d['remote_host'] as String?;
  final int? rp = (d['remote_port'] as num?)?.toInt();
  if (rh != null && rp != null) {
    final Map<String, dynamic>? remote = await DaemonJsonRpc.getInfo(
      rh,
      rp,
      connectTimeout: DaemonJsonRpc.probeConnectTimeout,
      requestTimeout: DaemonJsonRpc.probeRequestTimeout,
      quiet: true,
    );
    if (DaemonJsonRpc.getInfoPayload(remote) != null) {
      debugPrint(
          '[WalletRpc] local daemon RPC unavailable — wallet FFI using remote $rh:$rp');
      return '$rh:$rp';
    }
  }
  if (localEp != null) {
    return '${localEp.host}:${localEp.port}';
  }
  return walletDaemonAddress(configData);
}

/// Wallet JSON-RPC via in-process `arqma_wallet_flutter_ffi` (`Wallet2ApiClient` / wallet2).
///
/// Build: `rust/tool/build_wallet_flutter_ffi.sh` (Arqma upstream per `rust/docs/NATIVE_WALLET2.md`).
/// Override library path with **`ARQMA_FLUTTER_WALLET_FFI`**.
final class ArqmaWalletRpcSession {
  ArqmaWalletRpcSession._native(
    this._native,
    this.rpcPbkdf2SaltHex,
    this._ffiWalletDir,
    this._ffiDaemonAddress,
    this._ffiNetworkCode,
  ) : _isolateClient = null;

  ArqmaWalletRpcSession._nativeIsolate(
    this._isolateClient,
    this.rpcPbkdf2SaltHex,
    this._ffiWalletDir,
    this._ffiDaemonAddress,
    this._ffiNetworkCode,
  ) : _native = null;

  final WalletNativeFfi? _native;
  final WalletFfiIsolateClient? _isolateClient;

  /// Saved for FFI re-[configure] after [closeWalletSession] / worker [reset].
  final String _ffiWalletDir;
  final String _ffiDaemonAddress;
  final int _ffiNetworkCode;
  bool _nativeFfiConfigured = true;

  /// PBKDF2 salt for GUI password checks (same triple shape as legacy RPC auth).
  final String rpcPbkdf2SaltHex;

  Future<void> _callLane = Future<void>.value();

  /// Always true — desktop wallet uses native FFI only (no `arqma-wallet-rpc` subprocess).
  bool get usesNativeFfi => true;

  /// Cleared when [tryStart] begins; explains why native mode did not activate.
  static String lastNativeStartupDiagnosis = '';

  static Future<ArqmaWalletRpcSession?> tryStart(
      Map<String, dynamic> configData) async {
    lastNativeStartupDiagnosis = '';
    if (kIsWeb) {
      return null;
    }
    final String? daemonAddr = await resolveWalletDaemonAddress(configData);
    if (daemonAddr == null || daemonAddr.isEmpty) {
      lastNativeStartupDiagnosis =
          'Configuration: daemon address missing (remote host/port or local bind not set — check gui/config.json / daemons).';
      debugPrint('[WalletRpc] missing daemon address in config');
      return null;
    }
    final String? wdir = walletFilesDir(configData);
    if (wdir == null || wdir.isEmpty) {
      lastNativeStartupDiagnosis =
          'Configuration: wallet directory missing in config.';
      debugPrint('[WalletRpc] missing wallet files directory');
      return null;
    }
    Directory(wdir).createSync(recursive: true);

    final (_, _, String saltHex) = generateWalletRpcAuthTriple();
    final String net =
        (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final int netCode = networkCodeForNetType(net);

    // Worker isolate keeps the UI responsive; heavy wallet2 calls use a large-stack pthread in Rust FFI.
    // `ARQMA_FLUTTER_FFI_NO_ISOLATE=1` forces UI-thread FFI (blocks Flutter during long calls).
    final ArqmaWalletRpcSession? fromIsolate =
        await _tryStartNativeFfiIsolate(wdir, daemonAddr, netCode, saltHex);
    if (fromIsolate != null) {
      return fromIsolate;
    }
    final ArqmaWalletRpcSession? fromMain =
        await _tryStartNativeFfiMain(wdir, daemonAddr, netCode, saltHex);
    if (fromMain != null) {
      debugPrint(
          '[WalletRpc] native wallet2 FFI on UI thread (worker isolate unavailable)');
      return fromMain;
    }

    lastNativeStartupDiagnosis =
        'Could not load `arqma_wallet_flutter_ffi` native library. '
        '${WalletNativeFfi.lastLoadFailureDetail.isNotEmpty ? "(${WalletNativeFfi.lastLoadFailureDetail}). " : ""}'
        'Run from the same folder as Arqma-Wallet.exe after `flutter build windows --release` '
        'or set `$kArqmaFlutterWalletFfiEnv` to the full path to the DLL. '
        'Windows GNU: ship MinGW dependency DLLs next to the exe.';
    debugPrint(
        '[WalletRpc] native FFI library not loaded (see earlier [WalletNativeFfi] lines)');
    return null;
  }

  static Future<ArqmaWalletRpcSession?> _tryStartNativeFfiIsolate(
    String wdir,
    String daemonAddr,
    int netCode,
    String saltHex,
  ) async {
    if (kIsWeb) {
      return null;
    }
    if (Platform.environment['ARQMA_FLUTTER_FFI_NO_ISOLATE'] == '1') {
      return null;
    }
    final WalletFfiIsolateClient? isolate = await WalletFfiIsolateClient.start();
    if (isolate == null) {
      debugPrint(
          '[WalletRpc] FFI worker isolate unavailable — using UI-thread FFI');
      return null;
    }
    try {
      if (!await isolate.load()) {
        await isolate.dispose();
        return null;
      }
      final int cfg = await isolate.configure(wdir, daemonAddr, netCode);
      if (cfg != 0) {
        await isolate.dispose();
        return null;
      }
      Map<String, dynamic>? lastLang;
      for (int i = 0; i < 120; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final Map<String, dynamic>? r =
            await isolate.callJsonRpc('get_languages', <String, dynamic>{});
        lastLang = r;
        if (walletJsonRpcNoError(r)) {
          debugPrint(
              '[WalletRpc] native wallet2 FFI ready on worker isolate (get_languages OK)');
          return ArqmaWalletRpcSession._nativeIsolate(
            isolate,
            saltHex,
            wdir,
            daemonAddr,
            netCode,
          );
        }
      }
      debugPrint(
          '[WalletRpc] FFI isolate: get_languages not OK after retries; last=$lastLang');
      await isolate.dispose();
      return null;
    } catch (e, st) {
      debugPrint('[WalletRpc] FFI isolate startup failed: $e\n$st');
      await isolate.dispose();
      return null;
    }
  }

  static Future<ArqmaWalletRpcSession?> _tryStartNativeFfiMain(
    String wdir,
    String daemonAddr,
    int netCode,
    String saltHex,
  ) async {
    final WalletNativeFfi? ffi = WalletNativeFfi.tryLoad();
    if (ffi == null) {
      return null;
    }
    final int cfg = ffi.configure(wdir, daemonAddr, netCode);
    if (cfg != 0) {
      ffi.reset();
      return null;
    }
    for (int i = 0; i < 120; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final Map<String, dynamic>? r =
          await ffi.callJsonRpc('get_languages', <String, dynamic>{});
      if (walletJsonRpcNoError(r)) {
        debugPrint('[WalletRpc] native wallet2 FFI ready (get_languages OK)');
        return ArqmaWalletRpcSession._native(
          ffi,
          saltHex,
          wdir,
          daemonAddr,
          netCode,
        );
      }
    }
    ffi.reset();
    return null;
  }

  Future<bool> _reconfigureNativeFfi() async {
    final WalletFfiIsolateClient? iso = _isolateClient;
    if (iso != null) {
      final int cfg = await iso.configure(
        _ffiWalletDir,
        _ffiDaemonAddress,
        _ffiNetworkCode,
      );
      if (cfg != 0) {
        debugPrint('[WalletRpc] FFI isolate re-configure failed (code=$cfg)');
      }
      return cfg == 0;
    }
    final WalletNativeFfi? nat = _native;
    if (nat == null) {
      return false;
    }
    final int cfg = nat.configure(
      _ffiWalletDir,
      _ffiDaemonAddress,
      _ffiNetworkCode,
    );
    _nativeFfiConfigured = cfg == 0;
    if (!_nativeFfiConfigured) {
      debugPrint('[WalletRpc] native FFI re-configure failed (code=$cfg)');
    }
    return _nativeFfiConfigured;
  }

  Future<Map<String, dynamic>?> call(String method, Object params) {
    final Future<Map<String, dynamic>?> op = _callLane
        .then((_) => _callUnserialized(method, params));
    _callLane = op.then((_) {}, onError: (_) {});
    return op;
  }

  Future<Map<String, dynamic>?> _callUnserialized(
      String method, Object params) async {
    final WalletFfiIsolateClient? iso = _isolateClient;
    if (iso != null) {
      return iso.callJsonRpc(method, params);
    }
    final WalletNativeFfi? n = _native;
    if (n != null) {
      if (!_nativeFfiConfigured) {
        if (!await _reconfigureNativeFfi()) {
          return null;
        }
      }
      return n.callJsonRpc(method, params);
    }
    return null;
  }

  Future<void> closeWalletSession(
      {int nativeCloseWatchdogMs = kNativeWalletCloseWatchdogMs}) async {
    final WalletFfiIsolateClient? iso = _isolateClient;
    if (iso != null) {
      try {
        await iso
            .callJsonRpc('close_wallet', <String, dynamic>{})
            .timeout(Duration(milliseconds: nativeCloseWatchdogMs));
      } catch (_) {}
      try {
        await iso.reset().timeout(const Duration(seconds: 3));
      } catch (_) {}
      try {
        await _reconfigureNativeFfi();
      } catch (e, st) {
        debugPrint('[WalletRpc] re-configure after closeWalletSession: $e\n$st');
      }
      return;
    }
    final WalletNativeFfi? nat = _native;
    if (nat == null) {
      await call('close_wallet', <String, dynamic>{});
      return;
    }
    if (kIsWeb) {
      await call('close_wallet', <String, dynamic>{});
      return;
    }
    Isolate? watchdog;
    try {
      watchdog = await Isolate.spawn<int>(
        _nativeWalletFfiResetWatchdogMain,
        nativeCloseWatchdogMs,
        debugName: 'arqma_wallet_close_watchdog',
      );
    } catch (e, st) {
      debugPrint('[WalletRpc] native close watchdog spawn failed: $e\n$st');
    }
    try {
      await call('close_wallet', <String, dynamic>{}).timeout(
        Duration(milliseconds: nativeCloseWatchdogMs),
      );
      try {
        watchdog?.kill(priority: Isolate.immediate);
      } catch (_) {}
      watchdog = null;
    } catch (_) {
      await Future<void>.delayed(
        Duration(milliseconds: nativeCloseWatchdogMs + 200),
      );
    } finally {
      try {
        watchdog?.kill(priority: Isolate.immediate);
      } catch (_) {}
    }
  }

  /// Reset native wallet FFI from a helper isolate — never call [WalletNativeFfi.reset] on the UI
  /// isolate while wallet2 may be scanning (blocks forever; [Future.timeout] does not help).
  Future<void> forceResetNativeFfi({int watchdogMs = 0}) async {
    final WalletFfiIsolateClient? iso = _isolateClient;
    if (iso != null) {
      if (watchdogMs <= 0) {
        unawaited(iso.dispose());
        return;
      }
      try {
        await iso
            .callJsonRpc('close_wallet', <String, dynamic>{})
            .timeout(const Duration(milliseconds: 500));
      } catch (_) {}
      try {
        await iso.reset().timeout(const Duration(seconds: 2));
      } catch (_) {}
      try {
        await _reconfigureNativeFfi();
      } catch (e, st) {
        debugPrint('[WalletRpc] re-configure after forceResetNativeFfi: $e\n$st');
      }
      return;
    }
    if (_native == null || kIsWeb) {
      return;
    }
    Isolate? watchdog;
    try {
      watchdog = await Isolate.spawn<int>(
        _nativeWalletFfiResetWatchdogMain,
        watchdogMs,
        debugName: 'arqma_wallet_force_reset',
      );
      await Future<void>.delayed(Duration(milliseconds: watchdogMs + 400));
      _nativeFfiConfigured = false;
      await _reconfigureNativeFfi();
    } catch (e, st) {
      debugPrint('[WalletRpc] forceResetNativeFfi: $e\n$st');
    } finally {
      try {
        watchdog?.kill(priority: Isolate.immediate);
      } catch (_) {}
    }
  }

  Future<void> shutdown() async {
    final WalletFfiIsolateClient? iso = _isolateClient;
    if (iso != null) {
      try {
        await closeWalletSession();
      } catch (_) {}
      try {
        await iso.dispose();
      } catch (_) {}
      return;
    }
    if (_native != null) {
      await forceResetNativeFfi(watchdogMs: 0);
    }
  }

  /// Tear down FFI without blocking the UI isolate (switch-account / app exit).
  Future<void> releaseNativeResources() => forceResetNativeFfi(watchdogMs: 0);
}
