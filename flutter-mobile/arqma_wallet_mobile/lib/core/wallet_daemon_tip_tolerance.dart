/// Wallet `getheight` often stays slightly below the daemon tip while work finishes. Same FFI/RPC
/// semantics on Windows, Linux, and macOS — use one threshold so UI + desktop bridge stay aligned.
const int kWalletDaemonTipToleranceBlocks = 2880;
