import 'package:flutter/foundation.dart';

import 'gateway_store.dart';

/// Narrow listenable for [GoRouter.refreshListenable].
///
/// [GatewayStore] notifies on every heartbeat (~5 s: wallet info, txs, daemon,
/// redundant `reset_wallet_status`). Wiring the full store forces GoRouter to
/// re-run redirects and rebuild route shells — the main source of tab / layout jank.
/// Only app bootstrap status and open-wallet session gate routing.
class GatewayRouterRefreshListenable extends ChangeNotifier {
  GatewayRouterRefreshListenable(GatewayStore store) : _store = store {
    _lastAppCode = _store.appStatusCode;
    _lastWalletCode = _walletStatusCode;
    _store.addListener(_onStoreChanged);
  }

  final GatewayStore _store;
  late int _lastAppCode;
  late int _lastWalletCode;

  int get _walletStatusCode =>
      (_store.wallet['status'] as Map?)?['code'] as int? ?? 1;

  void _onStoreChanged() {
    final int appCode = _store.appStatusCode;
    final int walletCode = _walletStatusCode;
    if (appCode == _lastAppCode && walletCode == _lastWalletCode) {
      return;
    }
    _lastAppCode = appCode;
    _lastWalletCode = walletCode;
    notifyListeners();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }
}
