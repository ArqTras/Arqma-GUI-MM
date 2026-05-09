import 'dart:io';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';

import 'arqma_executable_resolve.dart';
import 'arqma_paths.dart';
import 'wallet_json_rpc.dart';

/// Same random `rpc-login` shape as `wallet_process::generate_auth_triple` (160 bytes → 320 hex chars).
(String user, String pass, String salt) generateWalletRpcAuthTriple() {
  final Random rnd = Random.secure();
  final List<int> bytes = List<int>.generate(160, (_) => rnd.nextInt(256));
  final String s = bytes.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();
  return (s.substring(0, 64), s.substring(64, 128), s.substring(128, 192));
}

/// `wallet_process::wallet_daemon_addr` — `host:port` for `--daemon-address`.
String? walletDaemonAddress(Map<String, dynamic> configData) {
  final String net = (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
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

String? resolveWalletRpcExecutable() => resolveArqmaExecutable(ArqmaExecutableKind.walletRpc);

/// Started `arqma-wallet-rpc` child + authenticated JSON-RPC client (parity with subprocess path in Rust).
final class ArqmaWalletRpcSession {
  ArqmaWalletRpcSession._(this.process, this.client, this.rpcPbkdf2SaltHex);

  final Process process;
  final WalletJsonRpcClient client;

  /// Third segment of `generateWalletRpcAuthTriple` — same role as `WalletBackendState.wallet_salt` in Tauri (PBKDF2 salt).
  final String rpcPbkdf2SaltHex;

  static Future<ArqmaWalletRpcSession?> tryStart(Map<String, dynamic> configData) async {
    final String? exe = resolveWalletRpcExecutable();
    if (exe == null) {
      debugPrint(
        '[WalletRpc] executable not found (ARQMA_WALLET_RPC, ARQMA_BUILD_DIR, ARQMA_INSTALL_PREFIX, PATH, src-tauri/bin)',
      );
      return null;
    }
    final String? daemonAddr = walletDaemonAddress(configData);
    if (daemonAddr == null || daemonAddr.isEmpty) {
      debugPrint('[WalletRpc] missing daemon address in config');
      return null;
    }
    final String? wdir = walletFilesDir(configData);
    if (wdir == null || wdir.isEmpty) {
      debugPrint('[WalletRpc] missing wallet files directory');
      return null;
    }
    Directory(wdir).createSync(recursive: true);
    final (String user, String pass, String saltHex) = generateWalletRpcAuthTriple();
    final int rpcPort = walletRpcBindPort(configData);
    final int logLevel = walletRpcLogLevel(configData);
    final String net = (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';

    final Directory? logDir = Directory(wdir).parent.path.isEmpty ? null : Directory('${Directory(wdir).parent.path}${Platform.pathSeparator}logs');
    logDir?.createSync(recursive: true);
    final String? logFile = logDir != null ? '${logDir.path}${Platform.pathSeparator}arqma-wallet-rpc.log' : null;

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

    debugPrint('[WalletRpc] starting: $exe ${args.join(' ')}');
    late final Process proc;
    try {
      proc = await Process.start(
        exe,
        args,
      );
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
      final Map<String, dynamic>? r = await http.call('get_languages', <String, dynamic>{});
      if (walletJsonRpcNoError(r)) {
        debugPrint('[WalletRpc] ready (get_languages OK)');
        return ArqmaWalletRpcSession._(proc, http, saltHex);
      }
    }
    debugPrint('[WalletRpc] timeout waiting for get_languages');
    try {
      proc.kill();
    } catch (_) {}
    await proc.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => 0);
    return null;
  }

  Future<Map<String, dynamic>?> call(String method, Object params) => client.call(method, params);

  Future<void> shutdown() async {
    try {
      await call('close_wallet', <String, dynamic>{});
    } catch (_) {}
    try {
      process.kill();
    } catch (_) {}
    try {
      await process.exitCode.timeout(const Duration(seconds: 4), onTimeout: () => 0);
    } catch (_) {}
  }
}
