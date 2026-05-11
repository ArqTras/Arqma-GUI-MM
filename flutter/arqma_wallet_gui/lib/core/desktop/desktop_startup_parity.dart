import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'arqma_executable_resolve.dart';
import 'arqma_paths.dart';
import 'daemon_json_rpc.dart';
import '../utils/deep_merge.dart';

/// Outbound interface IP (same idea as `solo_pool::preferred_bind_ip` using UDP in Rust).
Future<String> preferredBindIp() async {
  try {
    final Socket s = await Socket.connect('8.8.8.8', 80,
        timeout: const Duration(seconds: 2));
    final String a = s.address.address;
    await s.close();
    return a;
  } catch (_) {
    return '127.0.0.1';
  }
}

/// Drops obsolete `pool.mining.uniform` (`solo_pool::strip_legacy_uniform_pool_option`).
void stripLegacyUniformPoolOption(Map<String, dynamic> config) {
  final Object? pool = config['pool'];
  if (pool is! Map) {
    return;
  }
  final Object? mining = pool['mining'];
  if (mining is! Map) {
    return;
  }
  mining.remove('uniform');
}

/// `startup_run`: fix empty / loopback pool bind IP.
Future<void> mergePoolBindIpIfNeeded(Map<String, dynamic> config) async {
  final Object? pool = config['pool'];
  if (pool is! Map) {
    return;
  }
  final Object? server = pool['server'];
  if (server is! Map) {
    return;
  }
  final Map<String, dynamic> serverM = Map<String, dynamic>.from(server);
  final String bind = '${serverM['bindIP'] ?? ''}'.trim();
  if (bind.isEmpty || bind == '0.0.0.0' || bind == '127.0.0.1') {
    serverM['bindIP'] = await preferredBindIp();
    pool['server'] = serverM;
  }
}

/// Force `wallet.rpc_bind_port` = 19999 on each startup (Tauri `startup_run`).
void mergeWalletRpcBindPort19999(Map<String, dynamic> config) {
  final Map<String, dynamic> patch = <String, dynamic>{
    'wallet': <String, dynamic>{'rpc_bind_port': 19999},
  };
  final dynamic merged = deepMergeMaps(config, patch);
  if (merged is Map) {
    config
      ..clear()
      ..addAll(Map<String, dynamic>.from(merged));
  }
}

bool _mainnetDaemonIsLocal(Map<String, dynamic> config) {
  final Object? dm = (config['daemons'] as Map?)?['mainnet'];
  if (dm is! Map) {
    return false;
  }
  return '${dm['type'] ?? ''}' == 'local';
}

/// Parity with `startup_run::apply_scan_and_remote` (updates `daemons.mainnet` when `app.scan`).
Future<void> applyScanAndFastestRemote(
    Map<String, dynamic> configData, dynamic remotes) async {
  if (_mainnetDaemonIsLocal(configData)) {
    return;
  }
  final Object? app = configData['app'];
  final bool scan = app is Map && app['scan'] == true;
  if (!scan) {
    return;
  }
  final List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
  if (remotes is List) {
    for (final Object? n in remotes) {
      if (n is! Map) {
        continue;
      }
      final Map<String, dynamic> m = Map<String, dynamic>.from(n);
      final String? h = m['host'] as String?;
      final int? p = (m['port'] as num?)?.toInt();
      if (h != null && h.isNotEmpty && p != null) {
        list.add(<String, dynamic>{'host': h, 'port': p});
      }
    }
  }
  final ({String host, int port})? best = await pickFastestRemote(list);
  if (best == null) {
    return;
  }
  final Object? daemons = configData['daemons'];
  if (daemons is! Map) {
    return;
  }
  final Object? mainnet = daemons['mainnet'];
  if (mainnet is! Map) {
    return;
  }
  final Map<String, dynamic> dm = Map<String, dynamic>.from(mainnet);
  dm['remote_host'] = best.host;
  dm['remote_port'] = best.port;
  daemons['mainnet'] = dm;
}

/// Same timing idea as `remote_scan::pick_fastest_remote` (fastest successful `get_info`).
Future<({String host, int port})?> pickFastestRemote(
    List<Map<String, dynamic>> remotes) async {
  if (remotes.isEmpty) {
    return null;
  }
  ({String host, int port, int ms})? best;
  for (final Map<String, dynamic> n in remotes) {
    final String? h = n['host'] as String?;
    final int? p = (n['port'] as num?)?.toInt();
    if (h == null || h.isEmpty || p == null) {
      continue;
    }
    final Stopwatch sw = Stopwatch()..start();
    try {
      final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(h, p)
          .timeout(const Duration(milliseconds: 2500));
      sw.stop();
      if (DaemonJsonRpc.getInfoPayload(r) == null) {
        continue;
      }
      final int ms = sw.elapsedMilliseconds;
      if (best == null || ms < best.ms) {
        best = (host: h, port: p, ms: ms);
      }
    } catch (_) {
      continue;
    }
  }
  if (best == null) {
    return null;
  }
  return (host: best.host, port: best.port);
}

enum DaemonReachableResult { ok, netMismatch, inaccessible }

/// Parity with `daemon_check::check_daemon_reachable`.
Future<DaemonReachableResult> checkDaemonReachable(
    Map<String, dynamic> config) async {
  final String net =
      (config['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final Map<String, dynamic>? d = _daemonEntryForNet(config, net);
  if (d == null) {
    return DaemonReachableResult.inaccessible;
  }
  final String typ = '${d['type'] ?? 'remote'}';
  if (typ == 'local') {
    return DaemonReachableResult.ok;
  }
  final ({String host, int port})? ep = daemonRpcHostPort(config);
  if (ep == null) {
    return DaemonReachableResult.inaccessible;
  }
  final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(
    ep.host,
    ep.port,
    connectTimeout: DaemonJsonRpc.probeConnectTimeout,
    requestTimeout: DaemonJsonRpc.probeRequestTimeout,
  );
  final Map<String, dynamic>? info = DaemonJsonRpc.getInfoPayload(r);
  if (info == null) {
    return DaemonReachableResult.inaccessible;
  }
  final String? resNet = _nettypeFromGetInfo(info);
  if (resNet == null) {
    return DaemonReachableResult.ok;
  }
  final String want = switch (net) {
    'stagenet' => 'stage',
    'testnet' => 'test',
    _ => 'main',
  };
  if (!resNet.contains(want)) {
    return DaemonReachableResult.netMismatch;
  }
  return DaemonReachableResult.ok;
}

String? _nettypeFromGetInfo(Map<String, dynamic> info) {
  final Object? a = info['nettype'] ?? info['net_type'];
  if (a is String && a.isNotEmpty) {
    return a.toLowerCase();
  }
  final Object? nested = info['result'];
  if (nested is Map) {
    final Object? b = nested['nettype'] ?? nested['net_type'];
    if (b is String && b.isNotEmpty) {
      return b.toLowerCase();
    }
  }
  return null;
}

/// `daemon_handler::arqmad_version_probe_str` — non-empty stdout from `arqmad --version`, else `unknown`.
Future<String> arqmadVersionProbeStr() async {
  final String? exe = resolveArqmaExecutable(ArqmaExecutableKind.daemon);
  if (exe == null) {
    return 'unknown';
  }
  try {
    final ProcessResult o = await Process.run(exe, <String>['--version']);
    if (o.exitCode != 0) {
      return 'unknown';
    }
    final String s = '${o.stdout}'.trim();
    return s.isEmpty ? 'unknown' : s;
  } catch (_) {
    return 'unknown';
  }
}

/// `daemon_process::set_current_net_to_remote` + persist.
Future<void> setCurrentNetDaemonTypeRemoteAndPersist(
    ArqmaPaths paths, Map<String, dynamic> configData) async {
  final String net =
      (configData['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final Object? daemons = configData['daemons'];
  if (daemons is! Map) {
    return;
  }
  final Object? dm = daemons[net];
  if (dm is! Map) {
    return;
  }
  final Map<String, dynamic> entry = Map<String, dynamic>.from(dm);
  entry['type'] = 'remote';
  daemons[net] = entry;
  await writeGuiConfigFile(paths, configData);
}

Map<String, dynamic>? _daemonEntryForNet(
    Map<String, dynamic> config, String net) {
  final Object? dm = (config['daemons'] as Map? ?? <dynamic, dynamic>{})[net];
  if (dm is! Map) {
    return null;
  }
  return Map<String, dynamic>.from(dm);
}

Future<void> writeGuiConfigFile(
    ArqmaPaths paths, Map<String, dynamic> configData) async {
  final File f = File(paths.configPath);
  await f.parent.create(recursive: true);
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(configData));
}

/// When remote bootstrap is unreachable, switch `local_remote` → `local` (Tauri `startup_run`).
Future<void> flipLocalRemoteToLocalAndPersist(
    ArqmaPaths paths, Map<String, dynamic> configData, String net) async {
  final Object? daemons = configData['daemons'];
  if (daemons is! Map) {
    return;
  }
  final Object? dm = daemons[net];
  if (dm is! Map) {
    return;
  }
  final Map<String, dynamic> m = Map<String, dynamic>.from(dm);
  m['type'] = 'local';
  daemons[net] = m;
  await writeGuiConfigFile(paths, configData);
}

bool poolServerEnabled(Map<String, dynamic> config) {
  final Object? pool = config['pool'];
  if (pool is! Map) {
    return false;
  }
  final Object? server = pool['server'];
  if (server is! Map) {
    return false;
  }
  return server['enabled'] == true;
}
