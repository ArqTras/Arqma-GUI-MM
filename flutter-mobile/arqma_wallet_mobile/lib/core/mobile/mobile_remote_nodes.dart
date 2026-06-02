import 'package:flutter/foundation.dart';

import '../desktop/daemon_json_rpc.dart';

/// Official Arqma public remote nodes (mainnet RPC port 19994).
const int kArqmaMainnetRemotePort = 19994;

const List<String> kMobileRemoteNodeHosts = <String>[
  'node1.arqma.com',
  'node2.arqma.com',
  'node3.arqma.com',
  'node4.arqma.com',
];

/// Startup probe order: node1 first, then node2, …
const List<String> kMobileRemoteBootstrapOrder = <String>[
  'node1.arqma.com',
  'node2.arqma.com',
  'node3.arqma.com',
  'node4.arqma.com',
];

const String kMobileDefaultRemoteHost = 'node1.arqma.com';

List<Map<String, dynamic>> mobileRemoteNodesJson() {
  return kMobileRemoteNodeHosts
      .map(
        (String host) => <String, dynamic>{
          'host': host,
          'port': kArqmaMainnetRemotePort,
        },
      )
      .toList();
}

bool isPresetMobileRemoteHost(String host) {
  return kMobileRemoteNodeHosts.contains(host.trim());
}

bool isAllowedMobileRemoteHost(String host) {
  return isPresetMobileRemoteHost(host);
}

/// Returns true when [host]:[port] answers `get_info`.
Future<bool> probeMobileRemoteReachable(String host, int port) async {
  try {
    final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(
      host,
      port,
      connectTimeout: const Duration(seconds: 4),
      requestTimeout: const Duration(seconds: 10),
    );
    if (DaemonJsonRpc.getInfoPayload(r) != null) {
      debugPrint('[mobile_remote] reachable $host:$port');
      return true;
    }
    debugPrint('[mobile_remote] no get_info payload from $host:$port');
  } catch (e, st) {
    debugPrint('[mobile_remote] $host:$port failed: $e\n$st');
  }
  return false;
}

/// Probes [hosts] in order; returns the first that answers `get_info` on [kArqmaMainnetRemotePort].
Future<({String host, int port})?> pickFirstReachableMobileRemote({
  List<String> hosts = kMobileRemoteBootstrapOrder,
}) async {
  for (final String host in hosts) {
    if (await probeMobileRemoteReachable(host, kArqmaMainnetRemotePort)) {
      return (host: host, port: kArqmaMainnetRemotePort);
    }
  }
  return null;
}

void _writeMobileRemoteDaemonEntry(
  Map<String, dynamic> config,
  String host,
  int port,
) {
  final String net =
      (config['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final Map<String, dynamic> daemons = Map<String, dynamic>.from(
      config['daemons'] as Map? ?? <String, dynamic>{});
  final Map<String, dynamic> entry = Map<String, dynamic>.from(
      daemons[net] as Map? ?? <String, dynamic>{});
  entry['type'] = 'remote';
  entry['remote_host'] = host;
  entry['remote_port'] = port;
  daemons[net] = entry;
  config['daemons'] = daemons;
}

/// Keeps the configured remote node when reachable; otherwise falls back to node1 → node2 → …
Future<bool> ensureReachableMobileRemoteInConfig(Map<String, dynamic> config) async {
  final String net =
      (config['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final Map<String, dynamic> entry = Map<String, dynamic>.from(
      (config['daemons'] as Map? ?? <String, dynamic>{})[net] as Map? ??
          <String, dynamic>{});
  final String configuredHost = '${entry['remote_host'] ?? ''}'.trim();
  final int configuredPort =
      int.tryParse('${entry['remote_port']}') ?? kArqmaMainnetRemotePort;

  if (configuredHost.isNotEmpty &&
      await probeMobileRemoteReachable(configuredHost, configuredPort)) {
    _writeMobileRemoteDaemonEntry(config, configuredHost, configuredPort);
    return true;
  }
  if (configuredHost.isNotEmpty) {
    debugPrint(
      '[mobile_remote] configured $configuredHost:$configuredPort unreachable, probing fallbacks',
    );
  }

  final ({String host, int port})? picked =
      await pickFirstReachableMobileRemote();
  if (picked == null) {
    return false;
  }
  _writeMobileRemoteDaemonEntry(config, picked.host, picked.port);
  return true;
}
