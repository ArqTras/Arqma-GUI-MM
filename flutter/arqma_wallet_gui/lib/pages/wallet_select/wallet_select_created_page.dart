import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';

/// Parity with `pages/wallet-select/created.vue`.
class WalletSelectCreatedPage extends StatelessWidget {
  const WalletSelectCreatedPage({super.key});

  Future<void> _copyAddress(BuildContext context, String address) async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(loc.tr('pages.wallet_select.created.copy_address')),
        content:
            Text(loc.tr('pages.wallet_select.created.copy_address_message')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(loc.tr('components.address_book_details.cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(
                  loc.tr('pages.wallet_select.created.copy_address_ok_label'))),
        ],
      ),
    );
    if (ok == true) {
      await api.writeText(address);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(loc.tr('pages.wallet_select.created.address_copied'))),
        );
      }
    }
  }

  Future<void> _copySecret(
      BuildContext context, String type, String value) async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc
                .tr('pages.wallet_select.created.error_copying_private_key'))),
      );
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text('Copy $type'),
        content: Text(
            loc.tr('pages.wallet_select.created.private_key_warning_message')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(loc.tr('components.address_book_details.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(loc.tr(
                'pages.wallet_select.created.private_key_warning_ok_label')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await api.writeText(value);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(loc.tr('pages.wallet_select.created.address_copied'))),
        );
      }
    }
  }

  Future<void> _openWallet(BuildContext context) async {
    final GatewayStore store = context.read<GatewayStore>();
    await Future<void>.delayed(const Duration(seconds: 1));
    store.setWalletSecret(
        <String, dynamic>{'mnemonic': '', 'spend_key': '', 'view_key': ''});
    if (context.mounted) {
      context.go('/wallet');
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final Map<String, dynamic> info = store.walletInfo;
    final Map<String, dynamic> secret = Map<String, dynamic>.from(
        store.wallet['secret'] as Map? ?? <String, dynamic>{});
    final String mnemonic = '${secret['mnemonic'] ?? ''}';
    final String viewKey = '${secret['view_key'] ?? ''}';
    final String spendKey = '${secret['spend_key'] ?? ''}';
    final String name = '${info['name'] ?? ''}';
    final String address = '${info['address'] ?? ''}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${loc.tr('pages.wallet_select.created.wallet')}: $name',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: SelectableText(address,
                      style: const TextStyle(fontSize: 13))),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                onPressed: address.isEmpty
                    ? null
                    : () => _copyAddress(context, address),
                tooltip: loc.tr('pages.wallet_select.created.copy_address'),
              ),
            ],
          ),
          if (mnemonic.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(loc.tr('pages.wallet_select.created.seed_words'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SelectableText(mnemonic, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Text(loc.tr('pages.wallet_select.created.save_to_secure_location'),
                style: const TextStyle(color: Colors.amber)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _copySecret(context, 'mnemonic', mnemonic),
              icon: const Icon(Icons.copy),
              label:
                  Text(loc.tr('pages.wallet_select.created.copy_seed_words')),
            ),
          ],
          const SizedBox(height: 12),
          ExpansionTile(
            title: Text(loc.tr('pages.wallet_select.created.advanced')),
            children: [
              if (viewKey != spendKey) ...[
                Text(loc.tr('pages.wallet_select.created.view_key'),
                    style: Theme.of(context).textTheme.titleSmall),
                Row(
                  children: [
                    Expanded(
                        child: SelectableText(viewKey,
                            style: const TextStyle(fontSize: 12))),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () =>
                          _copySecret(context, 'view_key', viewKey),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (!RegExp(r'^0*$').hasMatch(spendKey)) ...[
                Text(loc.tr('pages.wallet_select.created.spend_key'),
                    style: Theme.of(context).textTheme.titleSmall),
                Row(
                  children: [
                    Expanded(
                        child: SelectableText(spendKey,
                            style: const TextStyle(fontSize: 12))),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () =>
                          _copySecret(context, 'spend_key', spendKey),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _openWallet(context),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(loc.tr('pages.wallet_select.created.open_account')),
          ),
        ],
      ),
    );
  }
}
