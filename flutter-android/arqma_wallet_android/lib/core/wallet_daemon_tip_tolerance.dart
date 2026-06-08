/// Oxen `footer.vue`: `wallet.info.height < target_height - 1` — one block below daemon tip.
/// Same threshold for footer, [GatewayStore.isReady], and desktop defer band.
const int kWalletDaemonTipToleranceBlocks = 1;

/// Blocks behind [daemonTip] (0 when at or above tip).
int walletDaemonTipGapBlocks(int walletHeight, int daemonTip) {
  if (daemonTip <= 0) {
    return 0;
  }
  final int gap = daemonTip - walletHeight;
  return gap <= 0 ? 0 : gap;
}

/// Oxen footer: caught up when `height >= target - 1` (gap ≤ 1).
bool walletHeightNearDaemonTip(int walletHeight, int daemonTip) {
  if (daemonTip <= 0) {
    return false;
  }
  if (walletHeight >= daemonTip) {
    return true;
  }
  return daemonTip - walletHeight <= kWalletDaemonTipToleranceBlocks;
}

/// Oxen `isScanning`: behind tip by more than one block and height already known.
bool walletHeightScanningBehind(int walletHeight, int daemonTip) {
  if (daemonTip <= 0 || walletHeight <= 0) {
    return false;
  }
  return walletHeight < daemonTip - kWalletDaemonTipToleranceBlocks;
}
