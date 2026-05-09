import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../app_strings.dart';
import '../core/services/native_bridge.dart';
import '../core/theme/arqma_colors.dart';
import '../store/gateway_store.dart';
import '../widgets/format_arqma.dart';
import '../widgets/status_footer.dart';
import '../widgets/wallet_main_menu.dart';

/// Parity with `layouts/wallet/main.vue`.
class WalletMainLayout extends StatefulWidget {
  const WalletMainLayout({super.key, required this.child});

  final Widget child;

  @override
  State<WalletMainLayout> createState() => _WalletMainLayoutState();
}

class _WalletMainLayoutState extends State<WalletMainLayout> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NativeBridge>().backendSend('wallet', 'get_coin_price', {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GatewayStore>();
    final path = GoRouterState.of(context).uri.path;
    final price = store.coinPrice;
    final info = store.walletInfo;
    final balance = num.tryParse('${info['balance'] ?? 0}') ?? 0;
    final unlocked = num.tryParse('${info['unlocked_balance'] ?? 0}') ?? 0;

    Future<void> refreshPrice() async {
      await context.read<NativeBridge>().backendSend('wallet', 'get_coin_price', {});
    }

    Widget navBtn(String route, String label, IconData icon) {
      final active = path == route;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: active ? ArqmaColors.arqmaGreenSolid : ArqmaColors.arqmaGreenDarkSolid,
            foregroundColor: Colors.black87,
            minimumSize: const Size(100, 44),
          ),
          onPressed: () => context.go(route),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: 6),
              Icon(icon, size: 18),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 5),
              child: Image.asset('assets/images/arq_logo_with_padding.png', height: 52),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (price != 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(r'$', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300)),
                        FormatArqma(amount: balance * price, digits: 2),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: refreshPrice,
                          color: Colors.white70,
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FormatArqma(amount: balance),
                        const Text(' ARQ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300)),
                      ],
                    ),
                  if (price != 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FormatArqma(amount: balance),
                        const Text(' ARQ', style: TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  if (balance != unlocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Temporarily locked ${(balance - unlocked).abs()} ARQ',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: WalletMainMenu(),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.white),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  navBtn('/wallet', AppStrings.navTransactions, Icons.swap_horiz),
                  navBtn('/wallet/send', AppStrings.navSend, Icons.arrow_right_alt),
                  navBtn('/wallet/receive', AppStrings.navReceive, Icons.save_alt),
                  navBtn('/wallet/staking-pools', AppStrings.navStakingPools, Icons.arrow_right_alt),
                  navBtn('/wallet/addressbook', AppStrings.navAddressBook, Icons.person),
                  navBtn('/wallet/solo-pool', AppStrings.navSoloPool, Icons.engineering),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Wallet settings — parity pending')),
                      );
                    },
                    child: Text(info['name']?.toString().isNotEmpty == true ? '${info['name']}' : 'Wallet'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white24, height: 24),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: widget.child,
            ),
          ),
          const StatusFooter(),
        ],
      ),
    );
  }
}
