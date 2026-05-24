import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'dart:math' show Random;

import 'package:flutter/foundation.dart';

import 'arqma_executable_resolve.dart';
import 'arqma_paths.dart';
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

/// Wallet JSON-RPC: **native** `Wallet2ApiClient` via `arqma_wallet_flutter_ffi` (`.dll` / `.so` / `.dylib`; default on desktop).
///
/// There is **no** `arqma-wallet-rpc` subprocess unless you opt in with **`ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess`**
/// (debug / migration only).
///
/// Build the FFI library: `bash rust/tool/build_wallet_flutter_ffi.sh` (needs Arqma upstream per `rust/docs/NATIVE_WALLET2.md`).
/// Override discovery with **`ARQMA_FLUTTER_WALLET_FFI`**.
final class ArqmaWalletRpcSession {
  ArqmaWalletRpcSession._subprocess(
      this.process, this.client, this.rpcPbkdf2SaltHex)
      : _native = null;

  ArqmaWalletRpcSession._native(this._native, this.rpcPbkdf2SaltHex)
      : process = null,
        client = null;

  final Process? process;
  final WalletJsonRpcClient? client;
  final WalletNativeFfi? _native;

  /// PBKDF2 salt for GUI password checks (same triple shape as RPC subprocess path).
  final String rpcPbkdf2SaltHex;

  /// True when [WalletNativeFfi] is active (no `arqma-wallet-rpc` subprocess).
  bool get usesNativeFfi => _native != null;

  /// Cleared when [tryStart] begins; explains why native mode did not activate (shown in UI instead of guessing "missing DLL").
  static String lastNativeStartupDiagnosis = '';

  static Future<ArqmaWalletRpcSession?> tryStart(
      Map<String, dynamic> configData) async {
    lastNativeStartupDiagnosis = '';
    final String? daemonAddr = walletDaemonAddress(configData);
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

    final (String user, String pass, String saltHex) =
        generateWalletRpcAuthTriple();
    final String net =
        (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
    final int netCode = networkCodeForNetType(net);

    final bool useSubprocessOnly = !kIsWeb &&
        Platform.environment[kArqmaFlutterWalletRpcModeEnv] == 'subprocess';

    if (!kIsWeb && !useSubprocessOnly) {
      final WalletNativeFfi? ffi = WalletNativeFfi.tryLoad();
      if (ffi != null) {
        final int cfg = ffi.configure(wdir, daemonAddr, netCode);
        if (cfg == 0) {
          Map<String, dynamic>? lastLang;
          for (int i = 0; i < 120; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            final Map<String, dynamic>? r =
                await ffi.callJsonRpc('get_languages', <String, dynamic>{});
            lastLang = r;
            if (walletJsonRpcNoError(r)) {
              debugPrint(
                  '[WalletRpc] native wallet2 FFI ready (get_languages OK)');
              return ArqmaWalletRpcSession._native(ffi, saltHex);
            }
          }
          lastNativeStartupDiagnosis =
              'Native FFI loaded but `get_languages` did not succeed after retries '
              '(last response: ${lastLang ?? "<null>"}). Check daemon address $daemonAddr '
              'and wallet2 logs — this is usually not "missing DLL" if `.dll/.so` copied already. '
              'Windows GNU: confirm `libgcc_s_seh-1.dll`, `libstdc++-6.dll`, `libwinpthread-1.dll` next to `Arqma-Wallet.exe` (flat Release; legacy `lib\\\\` still supported). '
              'Legacy: `$kArqmaFlutterWalletRpcModeEnv=subprocess`.';
          debugPrint(
              '[WalletRpc] native FFI: get_languages not OK after retries; last=$lastLang '
              '(Windows GNU: also copy libgcc_s_seh-1.dll, libstdc++-6.dll, libwinpthread-1.dll from '
              'MSYS2 mingw64/bin next to Arqma-Wallet.exe). Not starting subprocess (set '
              '$kArqmaFlutterWalletRpcModeEnv=subprocess to use arqma-wallet-rpc)');
          ffi.reset();
        } else {
          lastNativeStartupDiagnosis =
              'Native FFI `configure` returned error code=$cfg '
              '(invalid wallet dir UTF-8, internal lock error, etc.). Daemon: $daemonAddr. '
              'Legacy: `$kArqmaFlutterWalletRpcModeEnv=subprocess`.';
          debugPrint(
              '[WalletRpc] native FFI configure failed (code=$cfg); not starting subprocess (set '
              '$kArqmaFlutterWalletRpcModeEnv=subprocess to use arqma-wallet-rpc)');
          ffi.reset();
        }
      } else {
        final String detail = WalletNativeFfi.lastLoadFailureDetail.trim();
        final String detailSuffix =
            detail.isNotEmpty ? ' ($detail). ' : ' ';
        if (!kIsWeb && Platform.isIOS) {
          lastNativeStartupDiagnosis =
              'Could not load `libarqma_wallet_flutter_ffi.framework` from Runner.app/Frameworks.$detailSuffix'
              'Rebuild with `bash rust/tool/build_mobile_wallet_ffi_ios.sh` then `flutter build ipa`. '
              'Optional: `$kArqmaFlutterWalletFfiEnv` = absolute path to the framework binary.';
        } else if (!kIsWeb && Platform.isAndroid) {
          lastNativeStartupDiagnosis =
              'Could not load Android wallet FFI library.$detailSuffix'
              'Optional: `$kArqmaFlutterWalletFfiEnv` = absolute path to `.so`.';
        } else {
          lastNativeStartupDiagnosis =
              'Could not load `arqma_wallet_flutter_ffi` native library.$detailSuffix'
              'Run from the same folder as Arqma-Wallet.exe after `flutter build windows --release` '
              'or set `$kArqmaFlutterWalletFfiEnv` to full path to DLL. '
              'Windows GNU: MinGW DLLs beside the exe. Legacy: `$kArqmaFlutterWalletRpcModeEnv=subprocess`.';
        }
        debugPrint(
            '[WalletRpc] native FFI library not loaded (see earlier [WalletNativeFfi] lines; '
            'Windows: missing MinGW runtime DLLs next to the exe is common). Not starting subprocess (set '
            '$kArqmaFlutterWalletRpcModeEnv=subprocess for legacy arqma-wallet-rpc)');
      }
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

  Future<Map<String, dynamic>?> call(String method, Object params) {
    final WalletNativeFfi? n = _native;
    if (n != null) {
      return n.callJsonRpc(method, params);
    }
    return client!.call(method, params);
  }

  /// Closes the wallet session. Subprocess mode uses HTTP JSON-RPC only.
  ///
  /// Native FFI: `close_wallet` runs synchronously inside the C entrypoint and can block
  /// the Dart UI isolate for a long time; [Future.timeout] does not preempt it. We spawn
  /// a short-lived [Isolate] that sleeps then calls [WalletNativeFfi.reset] (see Rust
  /// `arqma_wallet_ffi_call_json`: global `CLIENT` must not be held across `block_on`).
  Future<void> closeWalletSession(
      {int nativeCloseWatchdogMs = kNativeWalletCloseWatchdogMs}) async {
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
      await call('close_wallet', <String, dynamic>{});
    } catch (_) {
    } finally {
      try {
        watchdog?.kill(priority: Isolate.immediate);
      } catch (_) {}
    }
  }

  Future<void> shutdown() async {
    final WalletNativeFfi? n = _native;
    if (n != null) {
      try {
        await closeWalletSession();
      } catch (_) {}
      n.reset();
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
}
