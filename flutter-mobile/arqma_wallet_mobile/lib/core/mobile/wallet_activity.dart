import 'dart:async';

/// Coordinates wallet heartbeat / FFI work with visible UI (tabs, scroll, gestures).
abstract final class WalletActivity {
  static String? _activeWalletTab = '/wallet';
  static bool _userBusy = false;
  static bool _txListScrolling = false;
  static Timer? _userBusyClear;

  static void setActiveWalletTab(String path) {
    _activeWalletTab = path;
  }

  static bool get isTransactionsTabActive =>
      _activeWalletTab == null || _activeWalletTab == '/wallet';

  static void markUserInteraction() {
    _userBusy = true;
    _userBusyClear?.cancel();
    _userBusyClear = Timer(const Duration(milliseconds: 900), () {
      _userBusy = false;
    });
  }

  static void setTxListScrolling(bool scrolling) {
    _txListScrolling = scrolling;
  }

  /// True while the user is scrolling the tx list or recently touched the wallet UI.
  static bool get deferHeavyWalletWork => _userBusy || _txListScrolling;

  /// Periodic `get_transfers` at chain tip — defer when off the tx tab or interacting.
  static bool shouldDeferPeriodicTxRefresh({required bool urgent}) {
    if (urgent) {
      return false;
    }
    if (!isTransactionsTabActive) {
      return true;
    }
    return deferHeavyWalletWork;
  }
}
