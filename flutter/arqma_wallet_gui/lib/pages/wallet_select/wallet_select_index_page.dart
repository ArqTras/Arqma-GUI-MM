import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Parity with `pages/wallet-select/index.vue` (wallet list / actions — UI shell).
class WalletSelectIndexPage extends StatelessWidget {
  const WalletSelectIndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tile(context, 'Create new wallet', '/wallet-select/create'),
        _tile(context, 'Restore wallet from seed', '/wallet-select/restore'),
        _tile(context, 'Import view-only wallet', '/wallet-select/import-view-only'),
        _tile(context, 'Import wallet from file', '/wallet-select/import'),
        _tile(context, 'Import legacy wallet', '/wallet-select/import-legacy'),
        _tile(context, 'Import old GUI wallets', '/wallet-select/import-old-gui'),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => context.go('/wallet'),
          child: const Text('Open main wallet UI (dev)'),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, String label, String path) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ElevatedButton(
        onPressed: () => context.push(path),
        child: Align(alignment: Alignment.centerLeft, child: Text(label)),
      ),
    );
  }
}
