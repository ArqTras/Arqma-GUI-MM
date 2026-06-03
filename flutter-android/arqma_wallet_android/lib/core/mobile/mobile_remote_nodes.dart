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

/// Validates preset or custom remote daemon hostnames (blocks paths, traversal, localhost).
bool isValidMobileRemoteHost(String host) {
  final String h = host.trim().toLowerCase();
  if (h.isEmpty || h.length > 253) {
    return false;
  }
  if (isPresetMobileRemoteHost(h)) {
    return true;
  }
  if (h.contains('..') ||
      h.contains('/') ||
      h.contains('\\') ||
      h.contains(':') ||
      h.contains(' ') ||
      h.contains('\t')) {
    return false;
  }
  if (h == 'localhost' || h.endsWith('.local')) {
    return false;
  }
  const String label = r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)';
  final RegExp hostname = RegExp('^$label(?:\\.$label)*\$');
  return hostname.hasMatch(h);
}

bool isValidMobileRemotePort(int port) {
  return port == kArqmaMainnetRemotePort;
}

bool isAllowedMobileRemoteHost(String host) {
  return isValidMobileRemoteHost(host);
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
      isValidMobileRemoteHost(configuredHost) &&
      isValidMobileRemotePort(configuredPort) &&
      await probeMobileRemoteReachable(configuredHost, configuredPort)) {
    _writeMobileRemoteDaemonEntry(config, configuredHost, configuredPort);
    return true;
  }
  if (configuredHost.isNotEmpty) {
    if (!isValidMobileRemoteHost(configuredHost) ||
        !isValidMobileRemotePort(configuredPort)) {
      debugPrint(
        '[mobile_remote] configured $configuredHost:$configuredPort invalid, probing fallbacks',
      );
    } else {
      debugPrint(
        '[mobile_remote] configured $configuredHost:$configuredPort unreachable, probing fallbacks',
      );
    }
  }

  final ({String host, int port})? picked =
      await pickFirstReachableMobileRemote();
  if (picked == null) {
    return false;
  }
  _writeMobileRemoteDaemonEntry(config, picked.host, picked.port);
  return true;
}
