import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'arqma_executable_resolve.dart';
import 'arqma_paths.dart';
import 'daemon_json_rpc.dart';
import 'wallet_json_rpc.dart';

String _join(String a, String b, [String? c]) {
  final String sep = Platform.pathSeparator;
  if (c == null) {
    return '$a$sep$b';
  }
  return '$a$sep$b$sep$c';
}

/// Resolve `arqmad` — same rules as `native_bin::resolve_arqmad_exe` / `upstream_paths::resolve_daemon_path`.
String? resolveArqmadExecutable() =>
    resolveArqmaExecutable(ArqmaExecutableKind.daemon);

/// Build CLI args like `daemon_process::ensure_daemon_for_startup` (local mode).
List<String> buildArqmadArgs(Map<String, dynamic> configData, String net) {
  final Map<String, dynamic> app = Map<String, dynamic>.from(
      configData['app'] as Map? ?? <String, dynamic>{});
  final String dataDir = '${app['data_dir'] ?? ''}';
  final Map<String, dynamic> d = Map<String, dynamic>.from(
      (configData['daemons'] as Map? ?? <String, dynamic>{})[net] as Map? ??
          <String, dynamic>{});

  String strVal(String k, String def) => '${d[k] ?? def}';
  int intVal(String k, int def) =>
      (d[k] is num) ? (d[k] as num).toInt() : int.tryParse('${d[k]}') ?? def;

  final String p2pIp = strVal('p2p_bind_ip', '0.0.0.0');
  final int p2pP = intVal('p2p_bind_port', 19993);
  final String rpcIp = strVal('rpc_bind_ip', '127.0.0.1');
  final int rpcP = intVal('rpc_bind_port', 19994);
  final String outP = strVal('out_peers', '-1');
  final String inP = strVal('in_peers', '-1');
  final String limUp = strVal('limit_rate_up', '-1');
  final String limDown = strVal('limit_rate_down', '-1');
  final int logLv = (d['log_level'] is num)
      ? (d['log_level'] as num).toInt()
      : int.tryParse('${d['log_level']}') ?? 0;

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
///
/// [onDaemonProcessLaunched] runs once the child process has started and JSON-RPC host/port are
/// known — use it to assign [Process] tracking and start heartbeat **before** this future
/// completes, so the UI can receive `get_info` while startup still polls for first RPC success.
Future<({Process? process, String? error})> spawnLocalArqmadAndWait({
  required Map<String, dynamic> configData,
  required String net,
  void Function(Process process)? onDaemonProcessLaunched,
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
    // Parity with Tauri `daemon_process.rs`: `stdin(piped)`, `stdout(null)`, `stderr(null)`.
    // `detachedWithStdio` leaves stdout/stderr connected; if we never read them, `arqmad` can
    // block on pipe buffer fills before RPC binds — looks like "daemon never starts".
    process = await Process.start(
      exe,
      args,
      mode: ProcessStartMode.normal,
    );
    unawaited(process.stdout.drain());
    unawaited(process.stderr.drain());
  } catch (e) {
    return (process: null, error: 'Failed to start arqmad: $e');
  }
  final String netForMsg =
      (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final ({String host, int port})? ep = daemonRpcHostPort(configData);
  if (ep == null) {
    process.kill();
    return (
      process: null,
      error:
          'Missing daemon JSON-RPC target for net_type "$netForMsg" — check `daemons.$netForMsg` '
          '(remote needs remote_host/remote_port; local needs rpc_bind_ip/rpc_bind_port matching arqmad).',
    );
  }
  onDaemonProcessLaunched?.call(process);
  const Duration maxWait = Duration(seconds: 120);
  const Duration pollTick = Duration(milliseconds: 400);
  // Poll with **probe** timeouts: while RPC is down, long per-attempt budgets only block the UI
  // thread of startup (and duplicate heartbeat work). When the daemon is up, `get_info` returns
  // quickly; full Tauri-style budgets apply in [DesktopNativeBridge._heartbeatTick].
  final Duration spawnConnect = DaemonJsonRpc.probeConnectTimeout;
  final Duration spawnRequest = DaemonJsonRpc.probeRequestTimeout;
  final Stopwatch sw = Stopwatch()..start();
  int attempt = 0;
  int lastGetInfoErrLogMs = -1 << 30;
  while (sw.elapsed < maxWait) {
    attempt++;
    final Object? exitedOrDelay = await Future.any<Object?>(<Future<Object?>>[
      process.exitCode.then<Object?>((int code) => code),
      Future<Object?>.delayed(pollTick).then((_) => null),
    ]);
    if (exitedOrDelay is int) {
      return (
        process: null,
        error:
            'arqmad exited before JSON-RPC answered at ${ep.host}:${ep.port} (exit $exitedOrDelay). '
            'See daemon.log; confirm Settings daemon rpc_bind_ip / rpc_bind_port match this address.',
      );
    }
    final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(
      ep.host,
      ep.port,
      connectTimeout: spawnConnect,
      requestTimeout: spawnRequest,
    );
    if (r != null && !walletJsonRpcNoError(r)) {
      final int elapsedMs = sw.elapsedMilliseconds;
      if (attempt == 1 || elapsedMs - lastGetInfoErrLogMs >= 8000) {
        lastGetInfoErrLogMs = elapsedMs;
        debugPrint(
            '[DesktopNative] get_info JSON-RPC error at ${ep.host}:${ep.port}: ${r['error']}');
      }
    }
    final Map<String, dynamic>? info = DaemonJsonRpc.getInfoPayload(r);
    if (info != null) {
      return (process: process, error: null);
    }
    await Future<void>.delayed(pollTick);
  }
  return (
    process: process,
    error:
        'Timeout: no get_info at http://${ep.host}:${ep.port}/json_rpc after ${maxWait.inSeconds}s '
        '(arqmad still running). Verify Settings → daemon rpc_bind_ip / rpc_bind_port, firewall, and '
        'daemon.log under your data_dir …/logs/ (same path as arqmad --log-file in the process list).',
  );
}
