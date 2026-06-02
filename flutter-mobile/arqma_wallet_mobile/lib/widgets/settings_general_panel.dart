import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_api.dart';
import '../core/mobile/mobile_defaults.dart';
import '../core/mobile/mobile_remote_nodes.dart';
import '../core/theme/arqma_colors.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import 'arqma_field.dart';
import 'mobile_remote_node_picker.dart';

/// Parity with `components/settings_general.vue` — call [applySaveInit] from Welcome "Next"
/// (same as Vue `notifier` → `save()` chain).
class SettingsGeneralPanel extends StatefulWidget {
  const SettingsGeneralPanel({super.key});

  @override
  State<SettingsGeneralPanel> createState() => SettingsGeneralPanelState();
}

class SettingsGeneralPanelState extends State<SettingsGeneralPanel> {
  late Map<String, dynamic> _pending;
  late List<dynamic> _remotes;
  late Map<String, dynamic> _ethereum;
  String _ethereumNetworkIndex = '0';
  bool _expandedAdvanced = false;

  /// After folder picker; blocks overwriting paths from store until save clears it.
  bool _storagePathsTouchedByPicker = false;
  GatewayStore? _gatewayListenTarget;

  static Map<String, dynamic> _deepClone(Object? src) {
    if (src == null) {
      return <String, dynamic>{};
    }
    if (src is Map) {
      return Map<String, dynamic>.fromEntries(
        src.entries.map(
          (MapEntry<Object?, Object?> e) => MapEntry<String, dynamic>(
            e.key.toString(),
            _deepCloneValue(e.value),
          ),
        ),
      );
    }
    return <String, dynamic>{};
  }

  static dynamic _deepCloneValue(Object? value) {
    if (value is Map) {
      return _deepClone(value);
    }
    if (value is List) {
      return value
          .map((Object? e) => e is Map ? _deepClone(e) : e)
          .toList(growable: true);
    }
    return value;
  }

  bool get _mobileRemoteOnly => Platform.isIOS || Platform.isAndroid;

  Map<String, dynamic> _daemon() {
    final Map<String, dynamic> pc = _pending;
    final String net = '${(pc['app'] as Map?)?['net_type'] ?? 'mainnet'}';
    final Map<String, dynamic> daemons =
        Map<String, dynamic>.from(pc['daemons'] as Map? ?? {});
    daemons.putIfAbsent(net, () => <String, dynamic>{'type': 'remote'});
    pc['daemons'] = daemons;
    return daemons[net]! as Map<String, dynamic>;
  }

  Map<String, dynamic> _app() {
    _pending.putIfAbsent('app', () => <String, dynamic>{});
    return _pending['app'] as Map<String, dynamic>;
  }

  Map<String, dynamic> _walletCfg() {
    _pending.putIfAbsent('wallet', () => <String, dynamic>{});
    return _pending['wallet'] as Map<String, dynamic>;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bootstrapOnce();
    final GatewayStore g = context.read<GatewayStore>();
    if (_gatewayListenTarget != g) {
      _gatewayListenTarget?.removeListener(_onGatewayStoreChanged);
      _gatewayListenTarget = g;
      g.addListener(_onGatewayStoreChanged);
    }
  }

  @override
  void dispose() {
    _gatewayListenTarget?.removeListener(_onGatewayStoreChanged);
    super.dispose();
  }

  void _onGatewayStoreChanged() {
    if (!mounted || _storagePathsTouchedByPicker) {
      return;
    }
    final GatewayStore store = context.read<GatewayStore>();
    final Map<String, dynamic> p =
        Map<String, dynamic>.from(store.app['pending_config'] as Map? ?? {});
    final Map<String, dynamic> c =
        Map<String, dynamic>.from(store.app['config'] as Map? ?? {});
    final Map<String, dynamic> full = p.isNotEmpty ? p : c;
    final Map<String, dynamic>? srcApp = full['app'] as Map<String, dynamic>?;
    if (srcApp == null) {
      return;
    }
    var changed = false;
    _pending.putIfAbsent('app', () => <String, dynamic>{});
    final Map<String, dynamic> app = _pending['app'] as Map<String, dynamic>;
    final String nextDataDir = '${srcApp['data_dir'] ?? ''}';
    final String nextWalletDir = '${srcApp['wallet_data_dir'] ?? ''}';
    if ('${app['data_dir'] ?? ''}' != nextDataDir ||
        '${app['wallet_data_dir'] ?? ''}' != nextWalletDir) {
      _syncStoragePathsFromGateway(store);
      changed = true;
    }
    if (_mobileRemoteOnly && _syncRemoteDaemonFromGateway(full)) {
      changed = true;
    }
    if (changed) {
      setState(() {});
    }
  }

  /// Keeps settings UI aligned with backend after `apply_remote_node` / startup restart.
  bool _syncRemoteDaemonFromGateway(Map<String, dynamic> full) {
    final String net = '${(_pending['app'] as Map?)?['net_type'] ?? 'mainnet'}';
    final Map<String, dynamic>? srcDaemons = full['daemons'] as Map<String, dynamic>?;
    final Map<String, dynamic>? srcEntry =
        srcDaemons?[net] as Map<String, dynamic>?;
    if (srcEntry == null) {
      return false;
    }
    final Map<String, dynamic> daemons = Map<String, dynamic>.from(
        _pending['daemons'] as Map? ?? <String, dynamic>{});
    final Map<String, dynamic> entry = Map<String, dynamic>.from(
        daemons[net] as Map? ?? <String, dynamic>{'type': 'remote'});
    final String nextHost = '${srcEntry['remote_host'] ?? ''}'.trim();
    final int nextPort =
        int.tryParse('${srcEntry['remote_port']}') ?? kArqmaMainnetRemotePort;
    if ('${entry['remote_host'] ?? ''}'.trim() == nextHost &&
        (int.tryParse('${entry['remote_port']}') ?? kArqmaMainnetRemotePort) ==
            nextPort) {
      return false;
    }
    entry['type'] = 'remote';
    entry['remote_host'] = nextHost;
    entry['remote_port'] = nextPort;
    daemons[net] = entry;
    _pending['daemons'] = daemons;
    return true;
  }

  bool _didBoot = false;

  void _bootstrapOnce() {
    if (_didBoot) {
      return;
    }
    _didBoot = true;
    final GatewayStore store = context.read<GatewayStore>();
    final Map<String, dynamic> p =
        Map<String, dynamic>.from(store.app['pending_config'] as Map? ?? {});
    final Map<String, dynamic> c =
        Map<String, dynamic>.from(store.app['config'] as Map? ?? {});
    _pending = p.isNotEmpty ? _deepClone(p) : _deepClone(c);
    _remotes = List<dynamic>.from(
        store.app['remotes'] as List<dynamic>? ?? const <dynamic>[]);
    _ethereum = _deepClone(store.raw['ethereum']);
    _ethereumNetworkIndex = '${_ethereum['ethereum_network_index'] ?? '0'}';
    if (_mobileRemoteOnly) {
      enforceMobileRemoteOnlyConfig(_pending);
    }
  }

  /// Welcome step 2 "Next" — `save_config_init` like Vue.
  Future<void> applySaveInit() => _save('save_config_init');

  /// Wallet menu / settings modal — `save_config` like Vue `notifier` + `save_config`.
  Future<void> applySaveRuntime() => _save('save_config');

  Future<void> _save(String method) async {
    final AppApi api = context.read<AppApi>();
    final GatewayStore store = context.read<GatewayStore>();
    try {
      await api.saveLoggingLevelToEnvironmentFile(
          '${_app()['loggingLevel'] ?? 'info'}');
      final Map<String, dynamic> newEth = _deepClone(_ethereum);
      newEth['ethereum_network_index'] = _ethereumNetworkIndex;
      await api.send('core', 'change_ethereum', newEth);
      await api.send('core', 'change_remotes', List<dynamic>.from(_remotes));
      final Map<String, dynamic> mergedPending = _deepClone(_pending);
      if (_mobileRemoteOnly) {
        enforceMobileRemoteOnlyConfig(mergedPending);
      }
      mergedPending['ethereum'] = newEth;
      await api.savePendingConfigToStore(mergedPending);
      await api.send('core', method, mergedPending);
      final Map<String, dynamic> appMap = Map<String, dynamic>.from(
          mergedPending['app'] as Map? ?? <String, dynamic>{});
      final int daysOfTx =
          int.tryParse('${appMap['daysOfTransactions'] ?? 1}') ?? 1;
      await api.send('core', 'set_daysOfTransactions',
          <String, dynamic>{'daysOfTransactions': daysOfTx});
      final int inactivityMin =
          int.tryParse('${appMap['inactivityTimeout'] ?? 5}') ?? 5;
      await api.send('core', 'set_inactivityTimeout',
          <String, dynamic>{'inactivityTimeout': inactivityMin});
      await api.notifierClear();
      store.setAppData(<String, dynamic>{
        'pending_config': mergedPending,
        'config': mergedPending,
        'remotes': List<dynamic>.from(_remotes),
      });
      if (mounted) {
        setState(() => _storagePathsTouchedByPicker = false);
      }
    } catch (e, st) {
      debugPrint('[SettingsGeneralPanel] save error $e\n$st');
      await api.logError('settings_general_panel', 'save', '$e');
    }
  }

  Future<void> _pickDataDir() async {
    final AppApi api = context.read<AppApi>();
    final String? p = await api.pickDirectory('${_app()['data_dir'] ?? ''}');
    if (p != null) {
      setState(() {
        _storagePathsTouchedByPicker = true;
        _app()['data_dir'] = p;
      });
    }
  }

  Future<void> _pickWalletDir() async {
    final AppApi api = context.read<AppApi>();
    final String? p =
        await api.pickDirectory('${_app()['wallet_data_dir'] ?? ''}');
    if (p != null) {
      setState(() {
        _storagePathsTouchedByPicker = true;
        _app()['wallet_data_dir'] = p;
      });
    }
  }

  /// `app.data_dir` / `app.wallet_data_dir` from gateway store (`config.json` via backend).
  void _syncStoragePathsFromGateway(GatewayStore store) {
    if (_storagePathsTouchedByPicker) {
      return;
    }
    final Map<String, dynamic> p =
        Map<String, dynamic>.from(store.app['pending_config'] as Map? ?? {});
    final Map<String, dynamic> c =
        Map<String, dynamic>.from(store.app['config'] as Map? ?? {});
    final Map<String, dynamic> full = p.isNotEmpty ? p : c;
    final Map<String, dynamic>? srcApp = full['app'] as Map<String, dynamic>?;
    if (srcApp == null) {
      return;
    }
    final Object? dd = srcApp['data_dir'];
    final Object? wd = srcApp['wallet_data_dir'];
    if ((dd == null || '$dd'.isEmpty) && (wd == null || '$wd'.isEmpty)) {
      return;
    }
    _pending.putIfAbsent('app', () => <String, dynamic>{});
    final Map<String, dynamic> app = _pending['app'] as Map<String, dynamic>;
    if (dd != null && '$dd'.isNotEmpty) {
      app['data_dir'] = dd;
    }
    if (wd != null && '$wd'.isNotEmpty) {
      app['wallet_data_dir'] = wd;
    }
  }

  void _setPreset(Map<String, dynamic> opt) {
    final Map<String, dynamic> d = _daemon();
    d['remote_host'] = opt['host'];
    d['remote_port'] = opt['port'];
    setState(() {});
  }

  void _removeRemote() {
    if (_remotes.length <= 1) {
      return;
    }
    final Map<String, dynamic> d = _daemon();
    final String host = '${d['remote_host']}';
    if (!_remotes.any((dynamic e) => '${(e as Map)['host']}' == host)) {
      return;
    }
    setState(() {
      _remotes.removeWhere((dynamic e) => '${(e as Map)['host']}' == host);
      if (_remotes.isNotEmpty) {
        _setPreset(_remotes.first as Map<String, dynamic>);
      }
    });
  }

  void _addRemote() {
    final Map<String, dynamic> d = _daemon();
    final String host = '${d['remote_host']}';
    final int port = int.tryParse('${d['remote_port']}') ?? 0;
    if (_remotes.any((dynamic e) => '${(e as Map)['host']}' == host)) {
      return;
    }
    setState(() => _remotes.add(<String, dynamic>{'host': host, 'port': port}));
  }

  Widget _lineField(Map<String, dynamic> target, String key,
      {bool disabled = false, TextInputType? keyboard, Key? fieldKey}) {
    return TextFormField(
      key: fieldKey,
      initialValue: '${target[key] ?? ''}',
      enabled: !disabled,
      keyboardType: keyboard,
      style: const TextStyle(color: ArqmaColors.textPrimary),
      decoration:
          const InputDecoration(border: InputBorder.none, isDense: true),
      onChanged: (String v) {
        if (keyboard == TextInputType.number) {
          final int? n = int.tryParse(v);
          target[key] = n ?? v;
        } else {
          target[key] = v;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final Map<String, dynamic> d = _daemon();
    final String t =
        _mobileRemoteOnly ? 'remote' : '${d['type'] ?? 'remote'}';
    if (_mobileRemoteOnly && d['type'] != 'remote') {
      d['type'] = 'remote';
    }

    String inactivityLabel() {
      final int v = int.tryParse('${_app()['inactivityTimeout'] ?? 5}') ?? 5;
      if (v == 31) {
        return loc
            .tr('components.general_settings.inactivity_timeout_infinity');
      }
      return '$v${loc.tr('components.general_settings.minutes')}';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_mobileRemoteOnly && t != 'remote') ...[
            Row(
              children: [
                Expanded(
                  child: ArqmaField(
                    label:
                        loc.tr('components.general_settings.local_daemon_ip'),
                    disable: true,
                    child: _lineField(d, 'rpc_bind_ip', disabled: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ArqmaField(
                    label:
                        loc.tr('components.general_settings.local_daemon_port'),
                    child: _lineField(d, 'rpc_bind_port',
                        keyboard: TextInputType.number),
                  ),
                ),
              ],
            ),
          ],
          if (_mobileRemoteOnly || t != 'local') ...[
            if (_mobileRemoteOnly) ...[
              MobileRemoteNodePicker(
                pendingConfig: _pending,
                onChanged: (Map<String, dynamic> cfg) {
                  setState(() => _pending = cfg);
                },
              ),
              Text(loc.tr('components.general_settings.remote_message'),
                  style: const TextStyle(color: ArqmaColors.textMuted)),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ArqmaField(
                      label: loc
                          .tr('components.general_settings.remote_node_host'),
                      disableMenu: false,
                      child: _lineField(d, 'remote_host'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ArqmaField(
                      label: loc
                          .tr('components.general_settings.remote_node_port'),
                      disableMenu: false,
                      child: _lineField(d, 'remote_port',
                          keyboard: TextInputType.number),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_drop_down,
                        color: ArqmaColors.textSecondary),
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: const Color(0xFF1d1d1d),
                        builder: (BuildContext c) => ListView(
                          children: _remotes.map((dynamic r) {
                            final Map<String, dynamic> m =
                                Map<String, dynamic>.from(r as Map);
                            return ListTile(
                              title: Text('${m['host']}:${m['port']}'),
                              onTap: () {
                                _setPreset(m);
                                Navigator.pop(c);
                              },
                            );
                          }).toList(),
                        ),
                      );
                      setState(() {});
                    },
                  ),
                ],
              ),
              Text(loc.tr('components.general_settings.warning'),
                  style: const TextStyle(color: ArqmaColors.textMuted)),
              Row(
                children: [
                  TextButton(
                      onPressed: _removeRemote,
                      child: Text(loc
                          .tr('components.general_settings.remove_node'))),
                  TextButton(
                      onPressed: _addRemote,
                      child: Text(
                          loc.tr('components.general_settings.add_node'))),
                ],
              ),
            ],
          ],
          if (_mobileRemoteOnly || t != 'local')
            ArqmaField(
              label: loc.tr('components.general_settings.remote_node_scan'),
              child: Switch(
                value: (_app()['scan'] as bool?) ?? false,
                onChanged: (bool v) => setState(() => _app()['scan'] = v),
              ),
            ),
          ArqmaField(
            label: loc.tr('components.general_settings.prompt_for_password'),
            child: Switch(
              value: (_app()['promptForPassword'] as bool?) ?? true,
              onChanged: (bool v) =>
                  setState(() => _app()['promptForPassword'] = v),
            ),
          ),
          ArqmaField(
            label: loc.tr('components.general_settings.debug_log_levels'),
            child: RadioGroup<String>(
              groupValue: '${_app()['loggingLevel'] ?? 'info'}',
              onChanged: (String? v) {
                if (v != null) {
                  setState(() => _app()['loggingLevel'] = v);
                }
              },
              child: const Row(
                children: <Widget>[
                  Radio<String>(value: 'error'),
                  Text('error'),
                  Radio<String>(value: 'info'),
                  Text('Info'),
                ],
              ),
            ),
          ),
          ArqmaField(
            label:
                loc.tr('components.general_settings.transactions_to_display'),
            child: Slider(
              value: (int.tryParse('${_app()['daysOfTransactions'] ?? 1}') ?? 1)
                  .toDouble()
                  .clamp(1, 30),
              min: 1,
              max: 30,
              divisions: 29,
              label:
                  '${_app()['daysOfTransactions']}${loc.tr('components.general_settings.days')}',
              onChanged: (double v) =>
                  setState(() => _app()['daysOfTransactions'] = v.round()),
            ),
          ),
          ArqmaField(
            label: loc.tr('components.general_settings.inactivity_timeout'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${loc.tr('components.general_settings.inactivity_timeout')} — ${loc.tr('components.general_settings.inactivity_timeout_infinity_note')}',
                  style: const TextStyle(
                      color: ArqmaColors.textMuted, fontSize: 11),
                ),
                Slider(
                  value:
                      (int.tryParse('${_app()['inactivityTimeout'] ?? 5}') ?? 5)
                          .toDouble()
                          .clamp(1, 31),
                  min: 1,
                  max: 31,
                  divisions: 30,
                  label: inactivityLabel(),
                  onChanged: (double v) =>
                      setState(() => _app()['inactivityTimeout'] = v.round()),
                ),
              ],
            ),
          ),
          ExpansionTile(
            initiallyExpanded: _expandedAdvanced,
            onExpansionChanged: (bool e) =>
                setState(() => _expandedAdvanced = e),
            title: Text(loc.tr('components.general_settings.advanced_options')),
            children: [
              if (!_mobileRemoteOnly) ...[
                RadioGroup<String>(
                  groupValue: t,
                  onChanged: (String? v) {
                    if (v != null) {
                      setState(() => d['type'] = v);
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      RadioListTile<String>(
                        title: Text(loc.tr(
                            'components.general_settings.remote_daemon_only')),
                        value: 'remote',
                      ),
                      RadioListTile<String>(
                        title: Text(loc.tr(
                            'components.general_settings.local_and_remote_daemon')),
                        value: 'local_remote',
                      ),
                      RadioListTile<String>(
                        title: Text(loc.tr(
                            'components.general_settings.local_daemon_only')),
                        value: 'local',
                      ),
                    ],
                  ),
                ),
                if (t == 'local_remote')
                  Text(
                      loc.tr('components.general_settings.local_remote_message'),
                      style:
                          const TextStyle(color: ArqmaColors.textSecondary)),
                if (t == 'local')
                  Text(loc.tr('components.general_settings.local_message'),
                      style: const TextStyle(color: ArqmaColors.textSecondary)),
                if (t == 'remote')
                  Text(loc.tr('components.general_settings.remote_message'),
                      style:
                          const TextStyle(color: ArqmaColors.textSecondary)),
              ],
              ArqmaField(
                label: loc.tr('components.general_settings.data_storage_path'),
                disableHover: true,
                child: Row(
                  children: [
                    Expanded(
                      child: _lineField(
                        _app(),
                        'data_dir',
                        disabled: true,
                        fieldKey:
                            ValueKey<String>('data_dir:${_app()['data_dir']}'),
                      ),
                    ),
                    TextButton(
                        onPressed: _pickDataDir,
                        child: Text(loc.tr(
                            'components.general_settings.select_location'))),
                  ],
                ),
              ),
              ArqmaField(
                label:
                    loc.tr('components.general_settings.wallet_storage_path'),
                disableHover: true,
                child: Row(
                  children: [
                    Expanded(
                      child: _lineField(
                        _app(),
                        'wallet_data_dir',
                        disabled: true,
                        fieldKey: ValueKey<String>(
                            'wallet_data_dir:${_app()['wallet_data_dir']}'),
                      ),
                    ),
                    TextButton(
                        onPressed: _pickWalletDir,
                        child: Text(loc.tr(
                            'components.general_settings.select_location'))),
                  ],
                ),
              ),
              Row(
                children: [
                  if (!_mobileRemoteOnly)
                    Expanded(
                      child: ArqmaField(
                        label: loc
                            .tr('components.general_settings.daemon_log_level'),
                        child: _lineField(d, 'log_level',
                            disabled: t == 'remote',
                            keyboard: TextInputType.number),
                      ),
                    ),
                  if (!_mobileRemoteOnly) const SizedBox(width: 8),
                  Expanded(
                    child: ArqmaField(
                      label: loc
                          .tr('components.general_settings.wallet_log_level'),
                      child: _lineField(_walletCfg(), 'log_level',
                          keyboard: TextInputType.number),
                    ),
                  ),
                ],
              ),
              if (!_mobileRemoteOnly) ...[
                Row(
                  children: [
                    Expanded(
                        child: ArqmaField(
                            label: loc.tr(
                                'components.general_settings.max_incoming_peers'),
                            child: _lineField(d, 'in_peers',
                                disabled: t == 'remote',
                                keyboard: TextInputType.number))),
                    Expanded(
                        child: ArqmaField(
                            label: loc.tr(
                                'components.general_settings.max_outgoing_peers'),
                            child: _lineField(d, 'out_peers',
                                disabled: t == 'remote',
                                keyboard: TextInputType.number))),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: ArqmaField(
                            label: loc.tr(
                                'components.general_settings.limit_upload_rate'),
                            child: _lineField(d, 'limit_rate_up',
                                disabled: t == 'remote',
                                keyboard: TextInputType.number))),
                    Expanded(
                        child: ArqmaField(
                            label: loc.tr(
                                'components.general_settings.limit_download_rate'),
                            child: _lineField(d, 'limit_rate_down',
                                disabled: t == 'remote',
                                keyboard: TextInputType.number))),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: ArqmaField(
                            label: loc.tr(
                                'components.general_settings.daemon_p2p_port'),
                            child: _lineField(d, 'p2p_bind_port',
                                disabled: t == 'remote',
                                keyboard: TextInputType.number))),
                    Expanded(
                        child: ArqmaField(
                            label: loc.tr(
                                'components.general_settings.daemon_zmq_port'),
                            child: _lineField(d, 'zmq_rpc_bind_port',
                                disabled: t == 'remote',
                                keyboard: TextInputType.number))),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: ArqmaField(
                            label: loc.tr(
                                'components.general_settings.internal_wallet_port'),
                            child: _lineField(_app(), 'ws_bind_port',
                                keyboard: TextInputType.number))),
                    Expanded(
                        child: ArqmaField(
                            label: loc.tr(
                                'components.general_settings.wallet_rpc_port'),
                            child: _lineField(_walletCfg(), 'rpc_bind_port',
                                disabled: t == 'remote',
                                keyboard: TextInputType.number))),
                  ],
                ),
              ],
              ArqmaField(
                label: loc.tr('components.general_settings.choose_a_network'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        loc.tr(
                            'components.general_settings.choose_a_network_helper'),
                        style: const TextStyle(
                            color: ArqmaColors.textMuted, fontSize: 11)),
                    RadioGroup<String>(
                      groupValue: '${_app()['net_type'] ?? 'mainnet'}',
                      onChanged: (String? v) {
                        if (v != null) {
                          setState(() => _app()['net_type'] = v);
                        }
                      },
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          RadioListTile<String>(
                            title: Text('Main Net'),
                            value: 'mainnet',
                          ),
                          RadioListTile<String>(
                            title: Text('Stage Net'),
                            value: 'stagenet',
                          ),
                          RadioListTile<String>(
                            title: Text('Test Net'),
                            value: 'testnet',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
