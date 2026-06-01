import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_api.dart';
import '../core/mobile/mobile_remote_nodes.dart';
import '../core/theme/arqma_colors.dart';
import '../i18n/locale_controller.dart';
import 'arqma_field.dart';

/// Official remote nodes (node1–node4) or a custom host/port (mainnet RPC).
class MobileRemoteNodePicker extends StatefulWidget {
  const MobileRemoteNodePicker({
    super.key,
    required this.pendingConfig,
    required this.onChanged,
  });

  static const String customNodeKey = '__custom_remote__';

  final Map<String, dynamic> pendingConfig;
  final void Function(Map<String, dynamic> updated) onChanged;

  @override
  State<MobileRemoteNodePicker> createState() => _MobileRemoteNodePickerState();
}

class _MobileRemoteNodePickerState extends State<MobileRemoteNodePicker> {
  late TextEditingController _customHost;
  late TextEditingController _customPort;

  Map<String, dynamic> _daemonEntry() {
    final String net =
        '${(widget.pendingConfig['app'] as Map?)?['net_type'] ?? 'mainnet'}';
    final Map<String, dynamic> daemons = Map<String, dynamic>.from(
        widget.pendingConfig['daemons'] as Map? ?? <String, dynamic>{});
    daemons.putIfAbsent(net, () => <String, dynamic>{'type': 'remote'});
    return daemons[net]! as Map<String, dynamic>;
  }

  String _currentHost() {
    return '${_daemonEntry()['remote_host'] ?? kMobileDefaultRemoteHost}'.trim();
  }

  int _currentPort() {
    return int.tryParse('${_daemonEntry()['remote_port']}') ??
        kArqmaMainnetRemotePort;
  }

  bool _usingCustom() => !isPresetMobileRemoteHost(_currentHost());

  @override
  void initState() {
    super.initState();
    _customHost = TextEditingController(text: _currentHost());
    _customPort =
        TextEditingController(text: '${_currentPort()}');
  }

  @override
  void didUpdateWidget(covariant MobileRemoteNodePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pendingConfig != widget.pendingConfig) {
      _customHost.text = _currentHost();
      _customPort.text = '${_currentPort()}';
    }
  }

  @override
  void dispose() {
    _customHost.dispose();
    _customPort.dispose();
    super.dispose();
  }

  void _applyRemote(String host, int port) {
    final Map<String, dynamic> cfg =
        Map<String, dynamic>.from(widget.pendingConfig);
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
    entry['remote_host'] = host.trim();
    entry['remote_port'] = port;
    daemons[net] = entry;
    cfg['daemons'] = daemons;
    widget.onChanged(cfg);
    unawaited(
      context.read<AppApi>().send(
        'core',
        'apply_remote_node',
        <String, dynamic>{'host': host.trim(), 'port': port},
      ),
    );
  }

  void _selectPreset(String host) {
    _applyRemote(host, kArqmaMainnetRemotePort);
    setState(() {
      _customHost.text = host;
      _customPort.text = '$kArqmaMainnetRemotePort';
    });
  }

  void _applyCustomFromFields() {
    final String host = _customHost.text.trim();
    final int port =
        int.tryParse(_customPort.text.trim()) ?? kArqmaMainnetRemotePort;
    if (host.isEmpty) {
      return;
    }
    _applyRemote(host, port);
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final String selectedHost = _currentHost();
    final String groupValue = _usingCustom()
        ? MobileRemoteNodePicker.customNodeKey
        : selectedHost;

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
            groupValue: groupValue,
            title: Text(host),
            subtitle: Text('RPC :$kArqmaMainnetRemotePort'),
            onChanged: (String? v) {
              if (v != null) {
                _selectPreset(v);
              }
            },
          );
        }),
        RadioListTile<String>(
          dense: true,
          value: MobileRemoteNodePicker.customNodeKey,
          groupValue: groupValue,
          title: Text(loc.tr('components.general_settings.custom_remote_node')),
          onChanged: (String? v) {
            if (v != null) {
              setState(() {});
              if (_customHost.text.trim().isNotEmpty) {
                _applyCustomFromFields();
              }
            }
          },
        ),
        if (_usingCustom()) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: ArqmaField(
                  label: loc
                      .tr('components.general_settings.remote_node_host'),
                  child: TextFormField(
                    controller: _customHost,
                    style: const TextStyle(color: ArqmaColors.textPrimary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText: 'my-node.example.com',
                    ),
                    onFieldSubmitted: (_) => _applyCustomFromFields(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ArqmaField(
                  label:
                      loc.tr('components.general_settings.remote_node_port'),
                  child: TextFormField(
                    controller: _customPort,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: ArqmaColors.textPrimary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onFieldSubmitted: (_) => _applyCustomFromFields(),
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _applyCustomFromFields,
              child: Text(loc.tr('components.general_settings.apply_custom_node')),
            ),
          ),
        ],
      ],
    );
  }
}
