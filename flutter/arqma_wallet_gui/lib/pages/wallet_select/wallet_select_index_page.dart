import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../core/desktop/arqma_paths.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/address_identicon.dart';
import '../../widgets/app_loading.dart';
import '../../core/theme/arqma_colors.dart';

/// Parity with `pages/wallet-select/index.vue`.
class WalletSelectIndexPage extends StatefulWidget {
  const WalletSelectIndexPage({super.key});

  @override
  State<WalletSelectIndexPage> createState() => _WalletSelectIndexPageState();
}

class _WalletSelectIndexPageState extends State<WalletSelectIndexPage> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final GatewayStore store = context.read<GatewayStore>();
      final Map<String, dynamic>? merged = mergedFilesystemConfig(store.app);
      unawaited(
        context.read<AppApi>().send(
              'wallet',
              'list_wallets',
              merged ?? <String, dynamic>{},
            ),
      );
    });
    final GatewayStore store = context.read<GatewayStore>();
    store.addListener(_onWalletStatus);
    _sub = context
        .read<AppApi>()
        .bridge
        .backendReceive
        .listen((Map<String, dynamic> msg) {
      if (msg['event'] == 'reset_wallet_status' ||
          msg['event'] == 'set_wallet_error') {
        _onWalletStatus();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    context.read<GatewayStore>().removeListener(_onWalletStatus);
    super.dispose();
  }

  void _onWalletStatus() {
    if (!mounted) {
      return;
    }
    final Map<String, dynamic> st =
        context.read<GatewayStore>().wallet['status'] as Map<String, dynamic>;
    final int code = st['code'] as int? ?? 1;
    if (code == 0) {
      AppLoading.hide();
      context.go('/wallet');
    } else if (code == -1 || code == -22) {
      AppLoading.hide();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${st['message'] ?? ''}')),
      );
      context
          .read<GatewayStore>()
          .resetWalletStatus({'code': 1, 'message': null});
    }
  }

  Future<void> _openWallet(Map<String, dynamic> wallet) async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final String name = '${wallet['name']}';
    final bool pwdProt = wallet['password_protected'] != false;
    String? password = '';
    if (pwdProt) {
      password = await showDialog<String>(
        context: context,
        builder: (BuildContext c) {
          final TextEditingController pw = TextEditingController();
          return AlertDialog(
            title: Text(
                loc.tr('pages.wallet_select.index.open_wallet_password_title')),
            content: TextField(
              controller: pw,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: loc.tr(
                      'pages.wallet_select.index.open_wallet_password_message')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(loc
                    .tr('pages.wallet_select.index.open_wallet_cancel_label')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, pw.text),
                child: Text(
                    loc.tr('pages.wallet_select.index.open_wallet_ok_label')),
              ),
            ],
          );
        },
      );
      if (password == null) {
        return;
      }
    }
    AppLoading.show();
    await api.send('wallet', 'open_wallet',
        <String, dynamic>{'name': name, 'password': password});
  }

  Future<void> _copyAddress(String address) async {
    final AppApi api = context.read<AppApi>();
    final LocaleController loc = context.read<LocaleController>();
    await api.writeText(address);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(loc.tr('pages.wallet_select.index.copy_address_message'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final Map<String, dynamic> wallets =
        Map<String, dynamic>.from(store.raw['wallets'] as Map? ?? {});
    final List<dynamic> list =
        (wallets['list'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> directories =
        (wallets['directories'] as List<dynamic>?) ?? const <dynamic>[];

    final List<Map<String, String>> actions = <Map<String, String>>[
      <String, String>{
        'name': loc.tr('pages.wallet_select.index.create_new_account'),
        'path': '/wallet-select/create'
      },
      <String, String>{
        'name': loc.tr('pages.wallet_select.index.restore_account_from_seed'),
        'path': '/wallet-select/restore'
      },
      <String, String>{
        'name':
            loc.tr('pages.wallet_select.index.restore_account_from_viewkey'),
        'path': '/wallet-select/import-view-only',
      },
    ];
    if (directories.isNotEmpty) {
      actions.add(<String, String>{
        'name':
            loc.tr('pages.wallet_select.index.import_accounts_from_old_gui'),
        'path': '/wallet-select/import-old-gui',
      });
    }

    Widget walletRow(Map<String, dynamic> w) {
      return Card(
        color: const Color(0xFF161410),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: ArqmaColors.outlineDefault.withValues(alpha: 0.75),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: AddressIdenticon(address: '${w['address'] ?? ''}', size: 44),
          title: Text(
            '${w['name']}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: ArqmaColors.textPrimary,
            ),
          ),
          subtitle: Text(
            '${w['address']}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: ArqmaColors.textMuted,
              height: 1.35,
            ),
          ),
          onTap: () => _openWallet(w),
          trailing: PopupMenuButton<String>(
            onSelected: (String v) {
              if (v == 'open') {
                _openWallet(w);
              } else if (v == 'copy') {
                _copyAddress('${w['address']}');
              }
            },
            itemBuilder: (BuildContext c) => [
              PopupMenuItem<String>(
                  value: 'open',
                  child:
                      Text(loc.tr('pages.wallet_select.index.open_account'))),
              PopupMenuItem<String>(
                  value: 'copy',
                  child:
                      Text(loc.tr('pages.wallet_select.index.copy_address'))),
            ],
          ),
        ),
      );
    }

    final int appCode = store.appStatusCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `app.status.code == -1`: core startup failed (paths, daemon reachability, or similar). Same idea as
        // Tauri when the user must revisit the welcome flow — `/welcome` lets them fix dirs and node.
        if (appCode == -1)
          Material(
            color: const Color(0xFF3a2a0a),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: Color(0xFFdbd19c), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      loc.tr('pages.wallet_select.index.setup_required_banner'),
                      style: const TextStyle(
                          fontSize: 12, color: ArqmaColors.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/welcome'),
                    child: Text(loc
                        .tr('pages.wallet_select.index.setup_wizard_button')),
                  ),
                ],
              ),
            ),
          ),
        if (list.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 56),
                  child: Text(
                    loc.tr('pages.wallet_select.index.accounts'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: ArqmaColors.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const Spacer(),
                PopupMenuButton<Map<String, String>>(
                  icon: const Icon(Icons.add, color: ArqmaColors.arqmaGreenSolid),
                  onSelected: (Map<String, String> a) =>
                      context.push(a['path']!),
                  itemBuilder: (BuildContext c) => actions
                      .map((Map<String, String> a) =>
                          PopupMenuItem<Map<String, String>>(
                              value: a, child: Text(a['name']!)))
                      .toList(),
                ),
              ],
            ),
          ),
          const Divider(height: 24, color: ArqmaColors.dividerLine),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext c, int i) =>
                  walletRow(Map<String, dynamic>.from(list[i] as Map)),
            ),
          ),
        ] else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: actions
                  .map(
                    (Map<String, String> a) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ElevatedButton(
                        onPressed: () => context.push(a['path']!),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(a['name']!)),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}
