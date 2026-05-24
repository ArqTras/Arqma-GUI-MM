import 'dart:io';

import 'mobile_remote_nodes.dart';

/// Effective config for UI (footer, settings) — prefers saved [config], then [pending_config].
Map<String, dynamic> effectiveAppConfig(Map<String, dynamic> app) {
  final Object? config = app['config'];
  final Object? pending = app['pending_config'];
  if (config is Map) {
    final Map<String, dynamic> c = Map<String, dynamic>.from(config);
    if (c['daemons'] is Map) {
      return c;
    }
  }
  if (pending is Map) {
    return Map<String, dynamic>.from(pending);
  }
  if (config is Map) {
    return Map<String, dynamic>.from(config);
  }
  return <String, dynamic>{};
}

/// Daemon entry for [netType], with mobile default `remote` when type is missing.
Map<String, dynamic> daemonEntryForNet(
  Map<String, dynamic> cfg,
  String netType,
) {
  final Map<String, dynamic> daemons =
      Map<String, dynamic>.from(cfg['daemons'] as Map? ?? <String, dynamic>{});
  final Map<String, dynamic> entry = Map<String, dynamic>.from(
    daemons[netType] as Map? ?? <String, dynamic>{},
  );
  if (!entry.containsKey('type')) {
    entry['type'] = (Platform.isIOS || Platform.isAndroid) ? 'remote' : 'local';
  }
  return entry;
}

String remoteNodeLabel(Map<String, dynamic> cfg) {
  final String net =
      (cfg['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  final Map<String, dynamic> d = daemonEntryForNet(cfg, net);
  if ('${d['type']}' != 'remote') {
    return '';
  }
  final String host =
      '${d['remote_host'] ?? kMobileDefaultRemoteHost}'.trim();
  final int port =
      (d['remote_port'] as num?)?.toInt() ?? kArqmaMainnetRemotePort;
  return '$host:$port';
}
