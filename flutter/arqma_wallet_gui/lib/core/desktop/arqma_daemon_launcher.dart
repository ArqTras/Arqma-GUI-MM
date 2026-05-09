import 'dart:io';

import 'package:flutter/foundation.dart';

import 'arqma_executable_resolve.dart';
import 'arqma_paths.dart';
import 'daemon_json_rpc.dart';

String _join(String a, String b, [String? c]) {
  final String sep = Platform.pathSeparator;
  if (c == null) {
    return '$a$sep$b';
  }
  return '$a$sep$b$sep$c';
}

/// Resolve `arqmad` — same rules as `native_bin::resolve_arqmad_exe` / `upstream_paths::resolve_daemon_path`.
String? resolveArqmadExecutable() => resolveArqmaExecutable(ArqmaExecutableKind.daemon);

/// Build CLI args like `daemon_process::ensure_daemon_for_startup` (local mode).
List<String> buildArqmadArgs(Map<String, dynamic> configData, String net) {
  final Map<String, dynamic> app = Map<String, dynamic>.from(configData['app'] as Map? ?? <String, dynamic>{});
  final String dataDir = '${app['data_dir'] ?? ''}';
  final Map<String, dynamic> d =
      Map<String, dynamic>.from((configData['daemons'] as Map? ?? <String, dynamic>{})[net] as Map? ?? <String, dynamic>{});

  String strVal(String k, String def) => '${d[k] ?? def}';
  int intVal(String k, int def) => (d[k] is num) ? (d[k] as num).toInt() : int.tryParse('${d[k]}') ?? def;

  final String p2pIp = strVal('p2p_bind_ip', '0.0.0.0');
  final int p2pP = intVal('p2p_bind_port', 19993);
  final String rpcIp = strVal('rpc_bind_ip', '127.0.0.1');
  final int rpcP = intVal('rpc_bind_port', 19994);
  final String outP = strVal('out_peers', '-1');
  final String inP = strVal('in_peers', '-1');
  final String limUp = strVal('limit_rate_up', '-1');
  final String limDown = strVal('limit_rate_down', '-1');
  final int logLv = (d['log_level'] is num) ? (d['log_level'] as num).toInt() : int.tryParse('${d['log_level']}') ?? 0;

  final Directory mainData = Directory(dataDir);
  final Directory netDir = switch (net) {
    'stagenet' => Directory(_join(mainData.path, 'stagenet')),
    'testnet' => Directory(_join(mainData.path, 'testnet')),
    _ => mainData,
  };
  final Directory logs = Directory(_join(netDir.path, 'logs'));
  logs.createSync(recursive: true);
  final String logFile = _join(logs.path, 'daemon.log');

  final List<String> args = <String>[
    '--data-dir',
    dataDir,
    '--p2p-bind-ip',
    p2pIp,
    '--p2p-bind-port',
    '$p2pP',
    '--rpc-bind-ip',
    rpcIp,
    '--rpc-bind-port',
    '$rpcP',
    '--out-peers',
    outP,
    '--in-peers',
    inP,
    '--limit-rate-up',
    limUp,
    '--limit-rate-down',
    limDown,
    '--log-level',
    '$logLv',
  ];
  if (net == 'testnet') {
    args.add('--testnet');
  } else if (net == 'stagenet') {
    args.add('--stagenet');
  }
  args.addAll(<String>['--log-file', logFile]);
  if (rpcIp != '127.0.0.1') {
    args.add('--confirm-external-bind');
  }
  final String typ = strVal('type', 'local');
  if (typ == 'local_remote' && net == 'mainnet') {
    final String? rh = d['remote_host'] as String?;
    final int? rp = (d['remote_port'] as num?)?.toInt();
    if (rh != null && rh.isNotEmpty && rp != null) {
      args.addAll(<String>['--bootstrap-daemon-address', '$rh:$rp']);
    }
  }
  return args;
}

/// Spawn local `arqmad` (stdin left open like Tauri) and poll `get_info` until OK or timeout.
Future<({Process? process, String? error})> spawnLocalArqmadAndWait({
  required Map<String, dynamic> configData,
  required String net,
}) async {
  final String? exe = resolveArqmadExecutable();
  if (exe == null) {
    return (
      process: null,
      error:
          'arqmad binary not found. Set ARQMA_DAEMON, ARQMA_BUILD_DIR, ARQMA_INSTALL_PREFIX, PATH, or place arqmad under rust/tauri-app/src-tauri/bin/.',
    );
  }
  final List<String> args = buildArqmadArgs(configData, net);
  debugPrint('[DesktopNative] starting arqmad: $exe ${args.join(' ')}');
  late final Process process;
  try {
    // Keep stdin open (parity with Tauri `Stdio::piped()` — EOF can stop `arqmad` in GUI runs).
    process = await Process.start(
      exe,
      args,
      mode: ProcessStartMode.detachedWithStdio,
    );
  } catch (e) {
    return (process: null, error: 'Failed to start arqmad: $e');
  }
  final ({String host, int port})? ep = daemonRpcHostPort(configData);
  if (ep == null) {
    process.kill();
    return (process: null, error: 'Missing RPC host/port in configuration.');
  }
  for (int i = 0; i < 150; i++) {
    final Object? exitedOrDelay = await Future.any<Object?>(<Future<Object?>>[
      process.exitCode.then<Object?>((int code) => code),
      Future<Object?>.delayed(const Duration(milliseconds: 200)).then((_) => null),
    ]);
    if (exitedOrDelay is int) {
      return (
        process: null,
        error: 'arqmad process exited before get_info (exit $exitedOrDelay; see daemon.log).',
      );
    }
    final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(ep.host, ep.port);
    final Map<String, dynamic>? info = DaemonJsonRpc.result(r);
    if (info != null) {
      return (process: process, error: null);
    }
  }
  return (
    process: process,
    error: 'Timeout: local arqmad did not respond to get_info (check ports and daemon.log).',
  );
}
