import 'package:flutter/material.dart';

import '../pages/wallet/addressbook_page.dart';
import '../pages/wallet/receive_page.dart';
import '../pages/wallet/send_page.dart';
import '../pages/wallet/solo_pool_page.dart';
import '../pages/wallet/staking_pools_page.dart';
import '../pages/wallet/swap_page.dart';
import '../pages/wallet/txhistory_page.dart';
import 'wallet_keep_alive_tab.dart';

/// Desktop wallet tabs — [IndexedStack] + lazy first build + keep-alive.
class WalletTabBody extends StatefulWidget {
  const WalletTabBody({
    super.key,
    required this.activePath,
    required this.tabRoutes,
  });

  final String activePath;
  final List<String> tabRoutes;

  @override
  State<WalletTabBody> createState() => _WalletTabBodyState();
}

class _WalletTabBodyState extends State<WalletTabBody> {
  static final List<Widget Function()> _tabBuilders = <Widget Function()>[
    () => const TxHistoryPage(),
    () => const SendPage(),
    () => const ReceivePage(),
    () => const StakingPoolsPage(),
    () => const AddressBookPage(),
    () => const SoloPoolPage(),
  ];

  final List<Widget?> _builtTabs = List<Widget?>.filled(_tabBuilders.length, null);
  Widget? _swapTab;

  int _tabIndex(String path) {
    final int i = widget.tabRoutes.indexOf(path);
    return i < 0 ? 0 : i;
  }

  Widget _lazyTab(int index, bool active) {
    if (!active && _builtTabs[index] == null) {
      return const SizedBox.expand();
    }
    _builtTabs[index] ??= WalletKeepAliveTab(child: _tabBuilders[index]());
    return TickerMode(enabled: active, child: _builtTabs[index]!);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activePath == '/wallet/swap') {
      _swapTab ??= const WalletKeepAliveTab(child: SwapPage());
      return _swapTab!;
    }

    final int index = _tabIndex(widget.activePath);
    return IndexedStack(
      index: index,
      sizing: StackFit.expand,
      children: List<Widget>.generate(
        _tabBuilders.length,
        (int i) => _lazyTab(i, i == index),
      ),
    );
  }
}
