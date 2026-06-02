## Arqma Wallet FFI 1.0.11

Prebuilt **arqma-wallet-flutter-ffi** libraries for desktop and mobile builds.

### Changes

- **Wallet file safety**: refuse `store` while a background rescan/refresh job is running; `close_wallet` waits up to 90s for the background job before closing the session (reduces `.keys` corruption risk on iOS suspend/close).
- **Mutating RPC guard**: block `transfer_split`, `transfer`, `stake`, `sweep_all`, and related calls while `wallet_background_busy` is set.
- **Includes 1.0.10**: full rescan progress poller, `getheight` during background jobs, async refresh height polling.

**Full changelog:** https://github.com/ArqTras/Arqma-GUI-MM/compare/3b0a204...HEAD (wallet2_client + mobile bridge; source in Arqma-GUI-MM `rust/arqma-wallet-rpc`).

### Assets

| Platform | Archive |
|----------|---------|
| iOS | `arqma-wallet-ffi-ios-1.0.11.zip` |

Other platform zips may be added in a follow-up CI build from the same tag.

Checksums: `SHA256SUMS-ffi-1.0.11.txt`.
