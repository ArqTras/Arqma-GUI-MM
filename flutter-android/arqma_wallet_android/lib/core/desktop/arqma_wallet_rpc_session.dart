import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'dart:math' show Random;

import 'package:flutter/foundation.dart';

import 'arqma_executable_resolve.dart';
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

/// Wallet `--daemon-address`: probe local daemon when configured, else use remote when local is down.
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

int walletRpcBindPort(Map<String, dynamic> configData) {
  final Object? raw = (configData['wallet'] as Map?)?['rpc_bind_port'];
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  return int.tryParse('$raw') ?? 19999;
}

int walletRpcLogLevel(Map<String, dynamic> configData) {
  final Object? raw = (configData['wallet'] as Map?)?['log_level'];
  if (raw is int) {
    return raw.clamp(1, 4);
  }
  if (raw is num) {
    return raw.toInt().clamp(1, 4);
  }
  return int.tryParse('$raw')?.clamp(1, 4) ?? 1;
}

String? resolveWalletRpcExecutable() =>
    resolveArqmaExecutable(ArqmaExecutableKind.walletRpc);

void _setNativeLoadFailureDiagnosis() {
  final String detail = WalletNativeFfi.lastLoadFailureDetail.trim();
  final String detailSuffix = detail.isNotEmpty ? ' ($detail). ' : ' ';
  if (!kIsWeb && Platform.isIOS) {
    ArqmaWalletRpcSession.lastNativeStartupDiagnosis =
        'Could not load `libarqma_wallet_flutter_ffi.framework` from Runner.app/Frameworks.$detailSuffix'
        'Rebuild with `bash rust/tool/build_mobile_wallet_ffi_ios.sh` then `flutter build ipa`. '
        'Optional: `$kArqmaFlutterWalletFfiEnv` = absolute path to the framework binary.';
  } else if (!kIsWeb && Platform.isAndroid) {
    ArqmaWalletRpcSession.lastNativeStartupDiagnosis =
        'Could not load Android wallet FFI library.$detailSuffix'
        'Optional: `$kArqmaFlutterWalletFfiEnv` = absolute path to `.so`.';
  } else {
    ArqmaWalletRpcSession.lastNativeStartupDiagnosis =
        'Could not load `arqma_wallet_flutter_ffi` native library.$detailSuffix'
        'Legacy: `$kArqmaFlutterWalletRpcModeEnv=subprocess`.';
  }
}

/// Wallet JSON-RPC: native `Wallet2ApiClient` via `arqma_wallet_flutter_ffi` (default on mobile).
///
/// Subprocess `arqma-wallet-rpc` only when **`ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess`**.
final class ArqmaWalletRpcSession {
  ArqmaWalletRpcSession._subprocess(
    this.process,
    this.client,
    this.rpcPbkdf2SaltHex,
  )   : _native = null,
        _isolateClient = null,
        _ffiWalletDir = '',
        _ffiDaemonAddress = '',
        _ffiNetworkCode = 0,
        _nativeFfiConfigured = true;

  ArqmaWalletRpcSession._native(
    this._native,
    this.rpcPbkdf2SaltHex,
    this._ffiWalletDir,
    this._ffiDaemonAddress,
    this._ffiNetworkCode,
  )   : process = null,
        client = null,
        _isolateClient = null;

  ArqmaWalletRpcSession._nativeIsolate(
    this._isolateClient,
    this.rpcPbkdf2SaltHex,
    this._ffiWalletDir,
    this._ffiDaemonAddress,
    this._ffiNetworkCode,
  )   : process = null,
        client = null,
        _native = null;

  final Process? process;
  final WalletJsonRpcClient? client;
  final WalletNativeFfi? _native;
  final WalletFfiIsolateClient? _isolateClient;

  final String _ffiWalletDir;
  final String _ffiDaemonAddress;
  final int _ffiNetworkCode;
  bool _nativeFfiConfigured = true;

  final String rpcPbkdf2SaltHex;

  Future<void> _callLane = Future<void>.value();

  bool get usesNativeFfi => _native != null || _isolateClient != null;

  static String lastNativeStartupDiagnosis = '';

  static String lastConfiguredWalletDaemonAddress = '';

  Future<void> resetNativeFfiClient() => releaseNativeResources();

  static Future<ArqmaWalletRpcSession?> tryStart(
      Map<String, dynamic> configData) async {
    lastNativeStartupDiagnosis = '';
    lastConfiguredWalletDaemonAddress = '';
    final String? daemonAddr = await resolveWalletDaemonAddress(configData);
    if (daemonAddr == null || daemonAddr.isEmpty) {
      lastNativeStartupDiagnosis =
          'Configuration: daemon address missing (remote host/port or local bind not set — check gui/config.json / daemons).';
      debugPrint('[WalletRpc] missing daemon address in config');
      return null;
    }
    lastConfiguredWalletDaemonAddress = daemonAddr;
    final String? wdir = walletFilesDir(configData);
    if (wdir == null || wdir.isEmpty) {
      lastNativeStartupDiagnosis =
          'Configuration: wallet directory missing in config.';
      debugPrint('[WalletRpc] missing wallet files directory');
      return null;
    }
    Directory(wdir).createSync(recursive: true);

    final (String user, String pass, String saltHex) =
        generateWalletRpcAuthTriple();
    final String net =
        (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final int netCode = networkCodeForNetType(net);

    final bool useSubprocessOnly = !kIsWeb &&
        Platform.environment[kArqmaFlutterWalletRpcModeEnv] == 'subprocess';

    if (!kIsWeb && !useSubprocessOnly) {
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
      _setNativeLoadFailureDiagnosis();
      debugPrint(
          '[WalletRpc] native FFI startup failed (set '
          '$kArqmaFlutterWalletRpcModeEnv=subprocess for legacy arqma-wallet-rpc)');
      return null;
    }

    if (kIsWeb) {
      return null;
    }

    final String? exe = resolveWalletRpcExecutable();
    if (exe == null) {
      debugPrint(
        '[WalletRpc] subprocess mode: `arqma-wallet-rpc` not found (ARQMA_WALLET_RPC, PATH, or '
        '…/Contents/Resources/bin/arqma-wallet-rpc)',
      );
      return null;
    }

    final int rpcPort = walletRpcBindPort(configData);
    final int logLevel = walletRpcLogLevel(configData);

    final Directory? logDir = Directory(wdir).parent.path.isEmpty
        ? null
        : Directory(
            '${Directory(wdir).parent.path}${Platform.pathSeparator}logs');
    logDir?.createSync(recursive: true);
    final String? logFile = logDir != null
        ? '${logDir.path}${Platform.pathSeparator}arqma-wallet-rpc.log'
        : null;

    final List<String> args = <String>[
      '--rpc-login',
      '$user:$pass',
      '--rpc-bind-port',
      '$rpcPort',
      '--daemon-address',
      daemonAddr,
      '--log-level',
      '$logLevel',
      '--wallet-dir',
      wdir,
    ];
    if (logFile != null) {
      args.addAll(<String>['--log-file', logFile]);
    }
    if (net == 'testnet') {
      args.add('--testnet');
    } else if (net == 'stagenet') {
      args.add('--stagenet');
    }

    debugPrint('[WalletRpc] starting subprocess: $exe ${args.join(' ')}');
    late final Process proc;
    try {
      proc = await Process.start(
        exe,
        args,
        mode: ProcessStartMode.normal,
      );
      unawaited(proc.stdout.drain());
      unawaited(proc.stderr.drain());
    } catch (e) {
      debugPrint('[WalletRpc] spawn failed: $e');
      return null;
    }

    final WalletJsonRpcClient http = WalletJsonRpcClient(
      host: '127.0.0.1',
      port: rpcPort,
      user: user,
      pass: pass,
    );

    for (int i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final Map<String, dynamic>? r =
          await http.call('get_languages', <String, dynamic>{});
      if (walletJsonRpcNoError(r)) {
        debugPrint('[WalletRpc] subprocess ready (get_languages OK)');
        return ArqmaWalletRpcSession._subprocess(proc, http, saltHex);
      }
    }
    debugPrint('[WalletRpc] timeout waiting for get_languages');
    try {
      proc.kill();
    } catch (_) {}
    await proc.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => 0);
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
    if (client != null) {
      return client!.call(method, params);
    }
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
    if (client != null) {
      await call('close_wallet', <String, dynamic>{});
      return;
    }
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
    lastConfiguredWalletDaemonAddress = '';
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
      return;
    }
    try {
      await call('close_wallet', <String, dynamic>{});
    } catch (_) {}
    try {
      process?.kill();
    } catch (_) {}
    try {
      await process?.exitCode
          .timeout(const Duration(seconds: 4), onTimeout: () => 0);
    } catch (_) {}
  }

  Future<void> releaseNativeResources() => forceResetNativeFfi(watchdogMs: 0);
}
