import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../store/gateway_store.dart';
import '../widgets/app_loading.dart';

/// Listens to [GatewayStore.wallet] `status.code` like Vue watchers on `wallet.status`
/// (create / restore / import flows → `/wallet-select/created` on code `0`).
mixin WalletFlowListenerMixin<T extends StatefulWidget> on State<T> {
  GatewayStore? _walletFlowStore;
  Object? _walletFlowLastToken;
  void Function()? _walletFlowListener;
  String _walletFlowSuccessRoute = '/wallet-select/created';

  void attachWalletFlowListener(
      {String successRoute = '/wallet-select/created'}) {
    final GatewayStore store = context.read<GatewayStore>();
    detachWalletFlowListener();
    _walletFlowSuccessRoute = successRoute;
    _walletFlowStore = store;
    final Map<String, dynamic> st0 = Map<String, dynamic>.from(
        store.wallet['status'] as Map? ?? <String, dynamic>{});
    _walletFlowLastToken = Object.hash(st0['code'], st0['message']);
    void listener() {
      if (!mounted || _walletFlowStore == null) {
        return;
      }
      final Map<String, dynamic> st = Map<String, dynamic>.from(
          _walletFlowStore!.wallet['status'] as Map? ?? <String, dynamic>{});
      final int code = st['code'] as int? ?? 1;
      final Object token = Object.hash(code, st['message']);
      if (token == _walletFlowLastToken) {
        return;
      }
      _walletFlowLastToken = token;
      switch (code) {
        case 0:
          AppLoading.hide();
          context.go(_walletFlowSuccessRoute);
          break;
        case 1:
          break;
        default:
          AppLoading.hide();
          final String msg = '${st['message'] ?? ''}';
          if (msg.isNotEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(msg)));
          }
      }
    }

    _walletFlowListener = listener;
    store.addListener(listener);
  }

  void detachWalletFlowListener() {
    if (_walletFlowStore != null && _walletFlowListener != null) {
      _walletFlowStore!.removeListener(_walletFlowListener!);
    }
    _walletFlowStore = null;
    _walletFlowListener = null;
    _walletFlowLastToken = null;
  }

  @override
  void dispose() {
    detachWalletFlowListener();
    super.dispose();
  }
}
