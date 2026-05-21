import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/mobile/mobile_remote_nodes.dart';
import '../core/theme/arqma_colors.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';

/// Select one of the four official remote nodes (mainnet).
class MobileRemoteNodePicker extends StatelessWidget {
  const MobileRemoteNodePicker({
    super.key,
    required this.pendingConfig,
    required this.onChanged,
  });

  final Map<String, dynamic> pendingConfig;
  final void Function(Map<String, dynamic> updated) onChanged;

  String _currentHost() {
    final String net =
        '${(pendingConfig['app'] as Map?)?['net_type'] ?? 'mainnet'}';
    final Map<String, dynamic>? d =
        (pendingConfig['daemons'] as Map?)?[net] as Map<String, dynamic>?;
    final String host = '${d?['remote_host'] ?? kMobileDefaultRemoteHost}';
    return isAllowedMobileRemoteHost(host) ? host : kMobileDefaultRemoteHost;
  }

  void _selectHost(String host) {
    final Map<String, dynamic> cfg =
        Map<String, dynamic>.from(pendingConfig);
    final String net =
        '${(cfg['app'] as Map?)?['net_type'] ?? 'mainnet'}';
    final Map<String, dynamic> daemons =
        Map<String, dynamic>.from(cfg['daemons'] as Map? ?? <String, dynamic>{});
    final Map<String, dynamic> entry = Map<String, dynamic>.from(
        daemons[net] as Map? ??
            <String, dynamic>{
              'type': 'remote',
            });
    entry['type'] = 'remote';
    entry['remote_host'] = host;
    entry['remote_port'] = kArqmaMainnetRemotePort;
    daemons[net] = entry;
    cfg['daemons'] = daemons;
    onChanged(cfg);
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final String selected = _currentHost();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          loc.tr('components.general_settings.remote_node_host'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: ArqmaColors.textPrimary,
              ),
        ),
        const SizedBox(height: 8),
        ...kMobileRemoteNodeHosts.map((String host) {
          return RadioListTile<String>(
            dense: true,
            value: host,
            groupValue: selected,
            title: Text(host),
            subtitle: Text('RPC :$kArqmaMainnetRemotePort'),
            onChanged: (String? v) {
              if (v != null) {
                _selectHost(v);
              }
            },
          );
        }),
      ],
    );
  }
}

/// Read-only footer label for the active remote node.
class MobileRemoteNodeStatusChip extends StatelessWidget {
  const MobileRemoteNodeStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final GatewayStore store = context.watch<GatewayStore>();
    final String net =
        ((store.app['config'] as Map?)?['app'] as Map?)?['net_type'] as String? ??
            'mainnet';
    final Map<String, dynamic>? d =
        (store.app['config'] as Map?)?['daemons'] as Map<String, dynamic>?;
    final Map<String, dynamic>? entry = d?[net] as Map<String, dynamic>?;
    final String host =
        '${entry?['remote_host'] ?? kMobileDefaultRemoteHost}';
    return Chip(
      label: Text(host, style: const TextStyle(fontSize: 12)),
      backgroundColor: ArqmaColors.darkPanel,
    );
  }
}
