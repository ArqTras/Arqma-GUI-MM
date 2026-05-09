import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/app_loading.dart';

/// Parity with `pages/wallet-select/import-old-gui.vue`.
class WalletSelectImportOldGuiPage extends StatefulWidget {
  const WalletSelectImportOldGuiPage({super.key});

  @override
  State<WalletSelectImportOldGuiPage> createState() => _WalletSelectImportOldGuiPageState();
}

class _WalletSelectImportOldGuiPageState extends State<WalletSelectImportOldGuiPage> {
  late final List<_DirRow> _rows;
  GatewayStore? _store;
  int _lastImportCode = 1;
  bool _awaiting = false;
  void Function()? _listener;

  @override
  void initState() {
    super.initState();
    final GatewayStore store = context.read<GatewayStore>();
    _store = store;
    _lastImportCode = (store.raw['old_gui_import_status'] as Map)['code'] as int? ?? 1;
    _rows = _buildRows(store);
    void fn() {
      if (!mounted || _store == null) {
        return;
      }
      final Map<String, dynamic> st = Map<String, dynamic>.from(_store!.raw['old_gui_import_status'] as Map? ?? <String, dynamic>{});
      final int code = st['code'] as int? ?? 1;
      if (code == _lastImportCode) {
        return;
      }
      _lastImportCode = code;
      if (_awaiting && code == 0) {
        _awaiting = false;
        AppLoading.hide();
        final List<dynamic> failed = st['failed_wallets'] as List<dynamic>? ?? const <dynamic>[];
        final LocaleController loc = context.read<LocaleController>();
        for (final dynamic w in failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${loc.tr('pages.wallet_select.import_old_gui.failed_to_import_account')}: $w')),
          );
        }
        if (failed.isEmpty) {
          context.go('/wallet-select');
        }
      }
    }
    _listener = fn;
    store.addListener(fn);
  }

  List<_DirRow> _buildRows(GatewayStore store) {
    final List<dynamic> dirs = (store.raw['wallets'] as Map?)?['directories'] as List<dynamic>? ?? const <dynamic>[];
    return dirs.map((dynamic d) => _DirRow(directory: '$d', selected: false, net: 'mainnet')).toList();
  }

  @override
  void dispose() {
    if (_store != null && _listener != null) {
      _store!.removeListener(_listener!);
    }
    super.dispose();
  }

  static const List<Map<String, String>> _netChoices = <Map<String, String>>[
    <String, String>{'label': 'Main', 'value': 'mainnet'},
    <String, String>{'label': 'Staging', 'value': 'stagenet'},
    <String, String>{'label': 'Test', 'value': 'testnet'},
  ];

  Future<void> _import() async {
    final List<Map<String, dynamic>> selected = _rows
        .where((_DirRow r) => r.selected)
        .map(
          (_DirRow r) => <String, dynamic>{
            'directory': r.directory,
            'selected': r.selected,
            'type': r.net,
          },
        )
        .toList();
    if (selected.isEmpty) {
      return;
    }
    _awaiting = true;
    AppLoading.show();
    await context.read<AppApi>().send('wallet', 'copy_old_gui_wallets', <String, dynamic>{'wallets': selected});
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (BuildContext context, int i) {
                final _DirRow r = _rows[i];
                return Card(
                  color: const Color(0xFF1d1d1d),
                  child: ListTile(
                    leading: Checkbox(
                      value: r.selected,
                      onChanged: (bool? v) => setState(() => r.selected = v ?? false),
                    ),
                    title: Text(r.directory),
                    trailing: DropdownButton<String>(
                      value: r.net,
                      dropdownColor: const Color(0xFF1d1d1d),
                      items: _netChoices
                          .map(
                            (Map<String, String> o) => DropdownMenuItem<String>(
                              value: o['value'],
                              child: Text(o['label']!),
                            ),
                          )
                          .toList(),
                      onChanged: (String? v) {
                        if (v != null) {
                          setState(() => r.net = v);
                        }
                      },
                    ),
                    onTap: () => setState(() => r.selected = !r.selected),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _rows.any((_DirRow r) => r.selected) ? _import : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4caf50),
              foregroundColor: Colors.black87,
            ),
            child: Text(loc.tr('pages.wallet_select.import_old_gui.import_accounts')),
          ),
        ],
      ),
    );
  }
}

class _DirRow {
  _DirRow({required this.directory, required this.selected, required this.net});

  final String directory;
  bool selected;
  String net;
}
