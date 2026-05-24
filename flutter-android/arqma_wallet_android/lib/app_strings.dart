/// UI strings (Flutter port). Full i18n can mirror `src/i18n` later.
abstract final class AppStrings {
  static const confirmClose = "Are you sure you want to exit?";
  static const footerStatus = "Status";
  static const footerVersion = "Version";
  static const footerLanguage = "Language";
  static const footerDaemon = "Daemon";
  static const footerRemote = "Remote";
  static const footerWallet = "Wallet";
  static const footerBlocksLeft = "Blocks left: {n}";
  static const navTransactions = "Transactions";
  static const navSend = "Send";
  static const navReceive = "Receive";
  static const navStakingPools = "Staking pools";
  static const navAddressBook = "Address book";
  static const navSoloPool = "Solo pool";
  static const menuSwitchAccount = "Switch account";
  static const menuDaemonSettings = "Daemon settings";
  static const menuAbout = "About";
  static const menuExitWallet = "Exit wallet";
  static const aboutClose = "Close";
  static const initConnecting = "Connecting to backend…";
  static const initStartingWallet = "Starting wallet…";
  static const initReadingWalletList = "Reading wallet list…";
  static const initRecalculating = "Recalculating service nodes…";
  static const walletPagePlaceholder =
      "Screen parity with Vue is implemented incrementally; backend calls require the native bridge.";
}
