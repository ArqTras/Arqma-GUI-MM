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

/// Scan progress for UI (footer / tx banner). Never rounds to 100% while still behind tip.
double walletScanProgressPercent(int walletHeight, int daemonTip) {
  if (daemonTip <= 0) {
    return 0;
  }
  final int gap = walletDaemonTipGapBlocks(walletHeight, daemonTip);
  var pct = (100.0 * walletHeight) / daemonTip;
  if (gap > kWalletDaemonTipToleranceBlocks && walletHeight < daemonTip) {
    if (pct >= 100) {
      pct = 99.999;
    } else if (pct >= 99.9995) {
      pct = 99.999;
    }
  }
  return pct.clamp(0.0, 100.0);
}

String walletScanProgressPercentLabel(int walletHeight, int daemonTip) {
  final double pct = walletScanProgressPercent(walletHeight, daemonTip);
  if (pct >= 10) {
    return pct.toStringAsFixed(1);
  }
  return pct.toStringAsFixed(2);
}
