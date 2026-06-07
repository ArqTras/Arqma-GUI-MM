/// Wallet `getheight` often stays slightly below the daemon tip while work finishes. Same FFI/RPC
/// semantics on Windows, Linux, and macOS — use one threshold so UI + desktop bridge stay aligned.
const int kWalletDaemonTipToleranceBlocks = 2880;

/// Blocks behind [daemonTip] (0 when at or above tip).
int walletDaemonTipGapBlocks(int walletHeight, int daemonTip) {
  if (daemonTip <= 0) {
    return 0;
  }
  final int gap = daemonTip - walletHeight;
  return gap <= 0 ? 0 : gap;
}

/// Matches footer / [GatewayStore._walletRpcNearTip] — wallet scan UI treats this as caught up.
bool walletHeightNearDaemonTip(int walletHeight, int daemonTip) {
  if (daemonTip <= 0) {
    return false;
  }
  if (walletHeight >= daemonTip) {
    return true;
  }
  return daemonTip - walletHeight <= kWalletDaemonTipToleranceBlocks;
}
