import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../core/app_api.dart';
import '../core/validators/service_node_command.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import 'password_dialogs.dart';
import '../core/theme/arqma_colors.dart';

/// Parity with `components/wallet_settings.vue` (menu + core wallet operations).
class WalletSettingsButton extends StatefulWidget {
  const WalletSettingsButton({super.key});

  @override
  State<WalletSettingsButton> createState() => _WalletSettingsButtonState();
}

class _WalletSettingsButtonState extends State<WalletSettingsButton> {
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _awaitingPrivateKeys = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sub = context.read<AppApi>().bridge.backendReceive.listen(_onBridge);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onBridge(Map<String, dynamic> msg) {
    if (!mounted) {
      return;
    }
    final String? ev = msg['event'] as String?;
    if (ev == 'set_wallet_secret') {
      final Object? d = msg['data'];
      if (d is Map && _awaitingPrivateKeys) {
        _awaitingPrivateKeys = false;
        final Map<String, dynamic> s = Map<String, dynamic>.from(d);
        if ('${s['view_key']}' == '-1') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '${s['mnemonic'] ?? context.read<LocaleController>().tr('backend.Invalid_password')}')),
          );
          return;
        }
        unawaited(_showSecretDialog(s));
      }
      return;
    }
    if (ev != 'set_tx_status') {
      return;
    }
    final Map<String, dynamic> st =
        Map<String, dynamic>.from(msg['data'] as Map? ?? <String, dynamic>{});
    if ('${st['origin']}' != 'wallet_settings') {
      return;
    }
    final LocaleController loc = context.read<LocaleController>();
    final int code = st['code'] as int? ?? 0;
    final String message = '${st['message'] ?? ''}';
    switch (code) {
      case 99:
        unawaited(_onSweepFee(message));
        break;
      case 100:
      case 200:
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_walletSettingsMessage(loc, message))));
        break;
      case -99:
      case -100:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: Colors.red.shade900,
              content: Text(_walletSettingsMessage(loc, message))),
        );
        break;
      default:
        break;
    }
  }

  String _walletSettingsMessage(LocaleController loc, String raw) {
    if (raw.isEmpty) {
      return '';
    }
    if (raw.contains('.')) {
      return loc.tr(raw);
    }
    final String k = 'components.wallet_settings.$raw';
    final String t = loc.tr(k);
    return t == k ? raw : t;
  }

  Future<void> _onSweepFee(String feeMessage) async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(loc.tr('components.wallet_settings.sweep_all_proceed')),
        content: Text(
            '${loc.tr('components.wallet_settings.sweep_all_fee')} $feeMessage'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c, false);
              api.send('wallet', 'cancelTransaction',
                  <String, dynamic>{'type': 'sweepAll'});
            },
            child: Text(
                loc.tr('components.wallet_settings.sweep_all_cancel_label')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child:
                Text(loc.tr('components.wallet_settings.sweep_all_ok_label')),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await api.send('wallet', 'relay_sweepAll',
          <String, dynamic>{'origin': 'wallet_settings'});
    }
  }

  Future<void> _showSecretDialog(Map<String, dynamic> secret) async {
    final LocaleController loc = context.read<LocaleController>();
    await showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: Text(loc.tr('components.wallet_settings.show_private_keys')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ('${secret['mnemonic'] ?? ''}'.isNotEmpty) ...[
                Text(loc.tr('components.wallet_settings.seed_words'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                SelectableText('${secret['mnemonic']}'),
                const SizedBox(height: 12),
              ],
              if ('${secret['view_key']}' != '${secret['spend_key']}') ...[
                Text(loc.tr('components.wallet_settings.view_key'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                SelectableText('${secret['view_key']}'),
                const SizedBox(height: 12),
              ],
              if (!RegExp(r'^0*$')
                  .hasMatch('${secret['spend_key'] ?? ''}')) ...[
                Text(loc.tr('components.wallet_settings.spend_key'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                SelectableText('${secret['spend_key']}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(loc.tr('components.wallet_settings.close'))),
        ],
      ),
    );
  }

  Future<void> _privateKeys() async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final String? password = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: loc.tr('components.wallet_settings.show_private_keys'),
      noPasswordMessage: loc
          .tr('components.wallet_settings.show_password_confirmation_message'),
      okLabel: loc
          .tr('components.wallet_settings.show_password_confirmation_ok_label'),
    );
    if (password == null || !mounted) {
      return;
    }
    _awaitingPrivateKeys = true;
    await api.send(
        'wallet', 'get_private_keys', <String, dynamic>{'password': password});
  }

  Future<void> _changePassword() async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Map<String, String>? result = await showDialog<Map<String, String>>(
      context: context,
      builder: (BuildContext _) => _ChangeWalletPasswordDialog(
        loc: loc,
        scaffoldMessenger: messenger,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    await api.send('wallet', 'change_wallet_password', <String, dynamic>{
      'old_password': result['old'],
      'new_password': result['new'],
    });
  }

  Future<void> _rescan() async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    String mode = 'spent';
    final bool? pick = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c, void Function(void Function()) setLocal) {
          return AlertDialog(
            title: Text(loc.tr('components.wallet_settings.rescan_account')),
            content: RadioGroup<String>(
              groupValue: mode,
              onChanged: (String? v) =>
                  setLocal(() => mode = v ?? 'spent'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  RadioListTile<String>(
                    title: Text(loc.tr(
                        'components.wallet_settings.rescan_full_blockchain')),
                    value: 'full',
                  ),
                  RadioListTile<String>(
                    title: Text(loc.tr(
                        'components.wallet_settings.rescan_spent_outputs')),
                    value: 'spent',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: Text(loc.tr('composables.cancel'))),
              TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(loc.tr('components.wallet_settings.rescan'))),
            ],
          );
        },
      ),
    );
    if (pick != true || !mounted) {
      return;
    }
    bool didMutate = false;
    if (mode == 'full') {
      final bool? hard = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (BuildContext c) => AlertDialog(
          title: Text(loc.tr('components.wallet_settings.rescan_wallet_title')),
          content:
              Text(loc.tr('components.wallet_settings.rescan_wallet_message')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(loc.tr(
                    'components.wallet_settings.rescan_wallet_cancel_label'))),
            TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(loc
                    .tr('components.wallet_settings.rescan_wallet_ok_label'))),
          ],
        ),
      );
      if (hard == true) {
        // Wait until the confirmation route is fully removed; pushing [AppLoading] before this
        // finished caused `hide()` to pop the wrong overlay and leave this dialog stuck + spinner.
        await Future<void>.delayed(Duration.zero);
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 12),
              content: Text(loc
                  .tr('components.wallet_settings.rescan_blocking_notice')),
            ),
          );
        }
        // Let the snackbar / shell repaint before native `rescan_blockchain` monopolizes the isolate.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        try {
          await api.send(
              'wallet', 'rescan_blockchain', <String, dynamic>{'hard': true});
          didMutate = true;
        } catch (e, st) {
          debugPrint('[WalletSettings] rescan_blockchain failed: $e\n$st');
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text('$e')),
            );
          }
        }
      }
    } else {
      await Future<void>.delayed(Duration.zero);
      await WidgetsBinding.instance.endOfFrame;
      try {
        await api.send('wallet', 'rescan_spent', <String, dynamic>{});
        didMutate = true;
      } catch (e, st) {
        debugPrint('[WalletSettings] rescan_spent failed: $e\n$st');
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('$e')),
          );
        }
      }
    }
    if (didMutate && mounted) {
      _goWalletTransactionsHome();
    }
  }

  /// Uses [appNavigatorKey] so routing works even when [context] is under an overlay/dialog subtree.
  void _goWalletTransactionsHome() {
    void go() {
      final BuildContext? ctx = appNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        GoRouter.of(ctx).go('/wallet');
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    });
  }

  Future<void> _sweepAll() async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final String? password = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: loc.tr('components.wallet_settings.sweep_all'),
      noPasswordMessage: loc.tr('components.wallet_settings.sweep_all_proceed'),
      okLabel: loc.tr('components.wallet_settings.sweep_all_proceed_label'),
    );
    if (password == null || !mounted) {
      return;
    }
    await api.send('wallet', 'sweepAll', <String, dynamic>{
      'password': password,
      'do_not_relay': true,
      'origin': 'wallet_settings',
    });
  }

  Future<void> _saveWallet() async {
    await context
        .read<AppApi>()
        .send('wallet', 'save_wallet', <String, dynamic>{});
  }

  Future<void> _exportTransactions() async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final String? path = await api.pickDirectory('');
    if (path == null || path.isEmpty || !mounted) {
      return;
    }
    final String? password = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: loc.tr('components.wallet_settings.export_transactions'),
      noPasswordMessage: loc.tr(
          'components.wallet_settings.show_password_confirmation_export_transactions_message_one'),
      okLabel: loc.tr('components.wallet_settings.export_transactions'),
    );
    if (password == null || !mounted) {
      return;
    }
    await api.send('wallet', 'export_transactions',
        <String, dynamic>{'password': password, 'path': path});
  }

  Future<void> _deleteWallet() async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(loc.tr('components.wallet_settings.delete_account')),
        content:
            Text(loc.tr('components.wallet_settings.delete_account_message')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(loc.tr(
                  'components.wallet_settings.delete_account_cancel_label'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(loc
                  .tr('components.wallet_settings.delete_account_ok_label'))),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    final String? password = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: loc.tr('components.wallet_settings.delete_account'),
      noPasswordMessage: loc.tr(
          'components.wallet_settings.show_delete_account_password_confirmation_message'),
      okLabel: loc.tr(
          'components.wallet_settings.show_delete_account_password_confirmation_ok_label'),
    );
    if (password == null || !mounted) {
      return;
    }
    await api.send(
        'wallet', 'delete_wallet', <String, dynamic>{'password': password});
  }

  Future<void> _registerServiceNode() async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final TextEditingController cmd = TextEditingController();
    final String? password = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: loc.tr(
          'components.wallet_settings.show_register_service_node_password_confirmation_title'),
      noPasswordMessage: loc.tr(
          'components.wallet_settings.show_register_service_node_password_confirmation_message'),
      okLabel: loc.tr(
          'components.wallet_settings.show_register_service_node_password_confirmation_ok_label'),
    );
    if (password == null || !mounted) {
      return;
    }
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(loc.tr('components.wallet_settings.register_service_node')),
        content: TextField(
          controller: cmd,
          decoration: InputDecoration(
            labelText:
                loc.tr('components.wallet_settings.service_node_command'),
            hintText: loc.tr(
                'components.wallet_settings.service_node_command_placeholder'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(loc.tr('composables.cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('OK')),
        ],
      ),
    );
    if (go != true || !mounted) {
      cmd.dispose();
      return;
    }
    final String s = cmd.text.trim();
    cmd.dispose();
    if (!isValidRegisterServiceNodeCommand(s)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(loc
              .tr('components.wallet_settings.invalid_service_node_command'))));
      return;
    }
    await api.send('wallet', 'register_service_node',
        <String, dynamic>{'password': password, 'string': s});
    if (!mounted) {
      return;
    }
    final Map<String, dynamic> reg = Map<String, dynamic>.from(
      (context.read<GatewayStore>().raw['service_node_status']
              as Map<String, dynamic>?)?['registration'] as Map? ??
          <String, dynamic>{},
    );
    final int code = reg['code'] is int ? reg['code'] as int : 0;
    final String msg = '${reg['message'] ?? ''}'.trim();
    if (code == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loc.tr('components.wallet_settings.service_node_registering_message'),
          ),
        ),
      );
    } else if (msg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  Future<void> _keyImages() async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final String? choice = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => SimpleDialog(
        title: Text(loc.tr('components.wallet_settings.manage_key_images')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'export_all'),
            child: Text(loc.tr('components.wallet_settings.export_all')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'export_since'),
            child: Text(loc.tr('components.wallet_settings.export_since')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'import'),
            child: Text(loc.tr('components.wallet_settings.import')),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) {
      return;
    }
    String? path;
    bool exportAll = false;
    if (choice == 'import') {
      final FilePickerResult? r = await FilePicker.platform.pickFiles();
      if (r == null || r.files.isEmpty) {
        return;
      }
      path = r.files.single.path;
    } else {
      path = await api.pickDirectory('');
      exportAll = choice == 'export_all';
    }
    if (path == null || path.isEmpty || !mounted) {
      return;
    }
    final String? password = await PasswordDialogs.showPasswordConfirmation(
      context: context,
      api: api,
      locale: loc,
      title: loc.tr('components.wallet_settings.manage_key_images'),
      noPasswordMessage:
          '${loc.tr('components.wallet_settings.show_key_images_password_confirmation_message_one')} ${loc.tr(choice == 'import' ? 'components.wallet_settings.import' : 'components.wallet_settings.export')} ${loc.tr('components.wallet_settings.show_key_images_password_confirmation_message_two')}',
      okLabel: choice == 'import'
          ? loc.tr('components.wallet_settings.import')
          : loc.tr('components.wallet_settings.export'),
    );
    if (password == null || !mounted) {
      return;
    }
    if (choice == 'import') {
      await api.send('wallet', 'import_key_images',
          <String, dynamic>{'password': password, 'path': path});
    } else {
      await api.send('wallet', 'export_key_images', <String, dynamic>{
        'password': password,
        'path': path,
        'all': exportAll,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final bool ready = store.isReady;
    final bool canRescan = store.hasOpenWallet;
    final Map<String, dynamic> info = store.walletInfo;
    final String label = '${info['name'] ?? ''}'.isEmpty
        ? loc.tr('components.wallet_settings.settings')
        : '${info['name']}';

    return PopupMenuButton<String>(
      useRootNavigator: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(color: ArqmaColors.textSecondary)),
            const Icon(Icons.arrow_drop_down, color: ArqmaColors.textSecondary),
          ],
        ),
      ),
      onSelected: (String v) async {
        switch (v) {
          case 'keys':
            if (ready) {
              await _privateKeys();
            }
            break;
          case 'pw':
            if (ready) {
              await _changePassword();
            }
            break;
          case 'save':
            if (ready) {
              await _saveWallet();
            }
            break;
          case 'rescan':
            if (canRescan) {
              await _rescan();
            }
            break;
          case 'sweep':
            if (ready) {
              await _sweepAll();
            }
            break;
          case 'keysimg':
            if (ready) {
              await _keyImages();
            }
            break;
          case 'export':
            if (ready) {
              await _exportTransactions();
            }
            break;
          case 'delete':
            if (ready) {
              await _deleteWallet();
            }
            break;
          case 'reg':
            if (ready) {
              await _registerServiceNode();
            }
            break;
        }
      },
      itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
        PopupMenuItem(
            value: 'keys',
            enabled: ready,
            child:
                Text(loc.tr('components.wallet_settings.show_private_keys'))),
        PopupMenuItem(
            value: 'pw',
            enabled: ready,
            child: Text(loc.tr('components.wallet_settings.change_password'))),
        PopupMenuItem(
            value: 'save',
            enabled: ready,
            child: Text(loc.tr('components.wallet_settings.save_wallet'))),
        PopupMenuItem(
            value: 'rescan',
            enabled: canRescan,
            child: Text(loc.tr('components.wallet_settings.rescan_account'))),
        PopupMenuItem(
            value: 'sweep',
            enabled: ready,
            child: Text(loc.tr('components.wallet_settings.sweep_all'))),
        PopupMenuItem(
            value: 'keysimg',
            enabled: ready,
            child:
                Text(loc.tr('components.wallet_settings.manage_key_images'))),
        PopupMenuItem(
            value: 'export',
            enabled: ready,
            child:
                Text(loc.tr('components.wallet_settings.export_transactions'))),
        PopupMenuItem(
            value: 'reg',
            enabled: ready,
            child: Text(
                loc.tr('components.wallet_settings.register_service_node'))),
        PopupMenuItem(
            value: 'delete',
            enabled: ready,
            child: Text(loc.tr('components.wallet_settings.delete_account'))),
      ],
    );
  }
}

class _ChangeWalletPasswordDialog extends StatefulWidget {
  const _ChangeWalletPasswordDialog({
    required this.loc,
    required this.scaffoldMessenger,
  });

  final LocaleController loc;
  final ScaffoldMessengerState scaffoldMessenger;

  @override
  State<_ChangeWalletPasswordDialog> createState() =>
      _ChangeWalletPasswordDialogState();
}

class _ChangeWalletPasswordDialogState
    extends State<_ChangeWalletPasswordDialog> {
  late final TextEditingController _oldPw = TextEditingController();
  late final TextEditingController _newPw = TextEditingController();
  late final TextEditingController _newPw2 = TextEditingController();

  @override
  void dispose() {
    _oldPw.dispose();
    _newPw.dispose();
    _newPw2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.loc.tr('components.wallet_settings.change_password')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _oldPw,
              obscureText: true,
              decoration: InputDecoration(
                  labelText:
                      widget.loc.tr('components.wallet_settings.old_password')),
            ),
            TextField(
              controller: _newPw,
              obscureText: true,
              decoration: InputDecoration(
                  labelText:
                      widget.loc.tr('components.wallet_settings.new_password')),
            ),
            TextField(
              controller: _newPw2,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: widget.loc
                      .tr('components.wallet_settings.confirm_new_password')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.loc.tr('composables.cancel'))),
        TextButton(
          onPressed: () {
            if (_newPw.text != _newPw2.text) {
              widget.scaffoldMessenger.showSnackBar(SnackBar(
                  content: Text(widget.loc.tr(
                      'components.wallet_settings.invalid_change_password_not_match_message'))));
              return;
            }
            if (_newPw.text == _oldPw.text) {
              widget.scaffoldMessenger.showSnackBar(SnackBar(
                  content: Text(widget.loc.tr(
                      'components.wallet_settings.invalid_change_password_message'))));
              return;
            }
            Navigator.pop(context,
                <String, String>{'old': _oldPw.text, 'new': _newPw.text});
          },
          child: Text(widget.loc.tr('components.wallet_settings.change')),
        ),
      ],
    );
  }
}
