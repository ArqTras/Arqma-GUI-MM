import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_api.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import 'settings_general_panel.dart';

/// Parity with `components/settings.vue` (General + Peers when not remote-only).
Future<void> showDaemonSettingsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext c) => const _DaemonSettingsDialog(),
  );
}

class _DaemonSettingsDialog extends StatefulWidget {
  const _DaemonSettingsDialog();

  @override
  State<_DaemonSettingsDialog> createState() => _DaemonSettingsDialogState();
}

class _DaemonSettingsDialogState extends State<_DaemonSettingsDialog> {
  int _tab = 0;
  final GlobalKey<SettingsGeneralPanelState> _panelKey =
      GlobalKey<SettingsGeneralPanelState>();

  static bool _daemonIsRemote(GatewayStore store) {
    final Map<String, dynamic> cfg = Map<String, dynamic>.from(
        store.app['config'] as Map? ?? <String, dynamic>{});
    final Map<String, dynamic> app =
        Map<String, dynamic>.from(cfg['app'] as Map? ?? <String, dynamic>{});
    final String net = '${app['net_type'] ?? 'mainnet'}';
    final Map<String, dynamic> daemons = Map<String, dynamic>.from(
        cfg['daemons'] as Map? ?? <String, dynamic>{});
    final Map<String, dynamic> d =
        Map<String, dynamic>.from(daemons[net] as Map? ?? <String, dynamic>{});
    return '${d['type'] ?? 'remote'}' == 'remote';
  }

  Future<void> _saveAndClose(BuildContext context) async {
    await _panelKey.currentState?.applySaveRuntime();
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  String _peerHost(Map<String, dynamic> entry) {
    final String h = '${entry['host'] ?? ''}';
    if (h.isNotEmpty) {
      return h;
    }
    return '${entry['address'] ?? entry['ip'] ?? ''}';
  }

  Future<void> _onPeerTap(
      BuildContext context, Map<String, dynamic> entry) async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final String json = const JsonEncoder.withIndent('  ').convert(entry);
    final bool? wantBan = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: Text(loc.tr('components.settings.peer_details_title')),
        content: SizedBox(
          width: 420,
          height: 320,
          child: SingleChildScrollView(
              child:
                  SelectableText(json, style: const TextStyle(fontSize: 11))),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(
                  loc.tr('components.settings.peer_details_cancel_label'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(loc.tr('components.settings.peer_details_ok_label'))),
        ],
      ),
    );
    if (wantBan != true || !context.mounted) {
      return;
    }
    final TextEditingController seconds = TextEditingController(text: '3600');
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: Text(loc.tr('components.settings.peer_details_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.tr('components.settings.peer_details_message')),
            const SizedBox(height: 8),
            TextField(
              controller: seconds,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(
                  loc.tr('components.settings.peer_details_cancel_label'))),
          TextButton(
            onPressed: () =>
                Navigator.pop(c, int.tryParse(seconds.text.trim()) ?? 3600),
            child: Text(loc.tr('components.settings.peer_details_ok_label')),
          ),
        ],
      ),
    );
    seconds.dispose();
    if (picked == null || !context.mounted) {
      return;
    }
    final String host = _peerHost(entry);
    if (host.isEmpty) {
      return;
    }
    await api.send('daemon', 'ban_peer',
        <String, dynamic>{'host': host, 'seconds': picked});
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final bool remoteOnly = _daemonIsRemote(store);
    if (remoteOnly && _tab != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _tab = 0);
        }
      });
    }
    final List<dynamic> connections =
        (store.daemon['connections'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> bans =
        (store.daemon['bans'] as List<dynamic>?) ?? const <dynamic>[];

    return Dialog(
      backgroundColor: const Color(0xFF1a1a1a),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                  Expanded(
                      child: Text(loc.tr('components.settings.settings'),
                          style: Theme.of(context).textTheme.titleLarge)),
                  if (!remoteOnly)
                    ToggleButtons(
                      isSelected: <bool>[_tab == 0, _tab == 1],
                      onPressed: (int i) => setState(() => _tab = i),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(loc.tr('components.settings.general')),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(loc.tr('components.settings.peers')),
                        ),
                      ],
                    ),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: () => _saveAndClose(context),
                      child: Text(loc.tr('components.settings.save'))),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _tab == 0 || remoteOnly
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: SettingsGeneralPanel(key: _panelKey),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Text(loc.tr('components.settings.peer_list'),
                            style: Theme.of(context).textTheme.titleSmall),
                        if (connections.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(loc.tr(
                                'components.settings.no_daemon_connections')),
                          )
                        else
                          ...connections.map((dynamic e) {
                            final Map<String, dynamic> m =
                                Map<String, dynamic>.from(e as Map);
                            final String addr =
                                '${m['address'] ?? m['ip'] ?? m['host'] ?? ''}';
                            final String h =
                                '${m['height'] ?? m['live_time'] ?? ''}';
                            return Card(
                              color: const Color(0xFF151515),
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                title: Text(addr,
                                    style: const TextStyle(fontSize: 12)),
                                subtitle: Text(
                                    '${loc.tr('components.settings.height')}$h'),
                                onTap: () => _onPeerTap(context, m),
                              ),
                            );
                          }),
                        if (bans.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(loc.tr('components.settings.banned_peers'),
                              style: Theme.of(context).textTheme.titleSmall),
                          ...bans.map((dynamic e) {
                            final Map<String, dynamic> m =
                                Map<String, dynamic>.from(e as Map);
                            final String host = '${m['host'] ?? ''}';
                            final int sec =
                                (m['seconds'] as num?)?.toInt() ?? 0;
                            final String until = DateTime.now()
                                .add(Duration(seconds: sec))
                                .toLocal()
                                .toString();
                            return ListTile(
                              dense: true,
                              title: Text(host,
                                  style: const TextStyle(fontSize: 12)),
                              subtitle: Text(
                                  '${loc.tr('components.settings.banned_until')} $until'),
                            );
                          }),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
