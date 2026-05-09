import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/services/native_bridge.dart';
import '../store/gateway_store.dart';
import '../widgets/status_footer.dart';
import '../widgets/wallet_main_menu.dart';

/// Parity with `layouts/wallet-select/main.vue`.
class WalletSelectLayout extends StatelessWidget {
  const WalletSelectLayout({super.key, required this.child});

  final Widget child;

  String _titleForLocation(String path) {
    if (path.endsWith('/wallet-select') || path == '/wallet-select') {
      return 'Arqma';
    }
    if (path.contains('/create')) {
      return 'Create wallet';
    }
    if (path.contains('/restore')) {
      return 'Restore wallet';
    }
    if (path.contains('import-view-only')) {
      return 'Import view-only';
    }
    if (path.contains('import-legacy')) {
      return 'Import legacy';
    }
    if (path.contains('import-old-gui')) {
      return 'Import old GUI';
    }
    if (path.contains('/import')) {
      return 'Import wallet';
    }
    if (path.contains('/created')) {
      return 'Wallet created';
    }
    return 'Arqma';
  }

  bool _showMenu(String path) {
    return path.endsWith('/wallet-select') || path == '/wallet-select';
  }

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    final title = _titleForLocation(loc);
    final showMenu = _showMenu(loc);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: showMenu ? 56 : 48,
        leading: showMenu
            ? const Padding(
                padding: EdgeInsets.only(left: 4),
                child: WalletMainMenu(disableSwitchWallet: true),
              )
            : IconButton(
                icon: const Icon(Icons.reply, color: Colors.white),
                onPressed: () async {
                  final NativeBridge bridge = context.read<NativeBridge>();
                  await bridge.backendSend('wallet', 'close_wallet', {});
                  if (context.mounted) {
                    context.go('/wallet-select');
                    context.read<GatewayStore>().resetWalletDataDispatch();
                  }
                },
              ),
        title: title == 'Arqma'
            ? Image.asset(
                'assets/images/arq_logo_with_padding.png',
                height: 48,
              )
            : Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w300, fontSize: 16),
              ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.white),
        ),
      ),
      // Do not wrap [child] in [SingleChildScrollView]: several wallet-select pages use
      // [Column] + [Expanded] + [ListView], which require a bounded height from this [Expanded].
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
          const StatusFooter(),
        ],
      ),
    );
  }
}
