import 'package:flutter/material.dart';

/// Keeps off-screen wallet tab state (scroll, form fields) when using [IndexedStack].
class WalletKeepAliveTab extends StatefulWidget {
  const WalletKeepAliveTab({super.key, required this.child});

  final Widget child;

  @override
  State<WalletKeepAliveTab> createState() => _WalletKeepAliveTabState();
}

class _WalletKeepAliveTabState extends State<WalletKeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
