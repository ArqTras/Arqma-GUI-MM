import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../store/gateway_store.dart';

/// Whether this wallet tab is the one shown in [IndexedStack].
class WalletTabVisibility extends InheritedWidget {
  const WalletTabVisibility({
    super.key,
    required this.isActive,
    required super.child,
  });

  final bool isActive;

  static WalletTabVisibility? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WalletTabVisibility>();
  }

  @override
  bool updateShouldNotify(WalletTabVisibility oldWidget) =>
      isActive != oldWidget.isActive;
}

extension GatewayStoreContext on BuildContext {
  /// Like [Provider.of] watch, but inactive wallet tabs do not rebuild on heartbeat.
  GatewayStore watchGatewayStore() {
    final WalletTabVisibility? scope = WalletTabVisibility.maybeOf(this);
    if (scope != null && !scope.isActive) {
      return read<GatewayStore>();
    }
    return watch<GatewayStore>();
  }
}
