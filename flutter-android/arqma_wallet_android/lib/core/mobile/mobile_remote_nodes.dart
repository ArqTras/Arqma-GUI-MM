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

/// Probes [hosts] in order; returns the first that answers `get_info` on [kArqmaMainnetRemotePort].
Future<({String host, int port})?> pickFirstReachableMobileRemote({
  List<String> hosts = kMobileRemoteBootstrapOrder,
}) async {
  for (final String host in hosts) {
    try {
      final Map<String, dynamic>? r = await DaemonJsonRpc.getInfo(
        host,
        kArqmaMainnetRemotePort,
        connectTimeout: const Duration(seconds: 4),
        requestTimeout: const Duration(seconds: 10),
      );
      if (DaemonJsonRpc.getInfoPayload(r) != null) {
        debugPrint('[mobile_remote] reachable $host:$kArqmaMainnetRemotePort');
        return (host: host, port: kArqmaMainnetRemotePort);
      }
      debugPrint('[mobile_remote] no get_info payload from $host:$kArqmaMainnetRemotePort');
    } catch (e, st) {
      debugPrint('[mobile_remote] $host:$kArqmaMainnetRemotePort failed: $e\n$st');
    }
  }
  return null;
}

/// Sets mainnet `remote_host` / `remote_port` to the first reachable node (node1 → node2 → …).
Future<bool> ensureReachableMobileRemoteInConfig(Map<String, dynamic> config) async {
  final ({String host, int port})? picked =
      await pickFirstReachableMobileRemote();
  if (picked == null) {
    return false;
  }
  final String net =
      (config['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final Map<String, dynamic> daemons = Map<String, dynamic>.from(
      config['daemons'] as Map? ?? <String, dynamic>{});
  final Map<String, dynamic> entry = Map<String, dynamic>.from(
      daemons[net] as Map? ?? <String, dynamic>{});
  entry['type'] = 'remote';
  entry['remote_host'] = picked.host;
  entry['remote_port'] = picked.port;
  daemons[net] = entry;
  config['daemons'] = daemons;
  return true;
}
