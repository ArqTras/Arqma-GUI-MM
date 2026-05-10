Place arqmad.exe (Windows) or arqmad (Unix) here before `tauri build`, or run from repo root: `node build/copy-to-tauri-bins.js` after `./bin` contains those files from download/extract (script copies **arqmad only**).

**Flutter desktop:** `flutter build macos|linux|windows` copies the same files from this folder into the app bundle (`Contents/Resources/bin` on macOS, `bin/` next to the exe on Linux/Windows). The Stratum helper `arqma_flutter_solo_pool` may live here or under `src-tauri/target/<profile>/` (macOS build script tries both). Override paths at runtime with `ARQMA_DAEMON`, `ARQMA_WALLET_RPC`, `ARQMA_FLUTTER_SOLO_POOL` if needed.

Windows: if Cargo build fails with "Proces nie może uzyskać dostępu..." (Win32 os error 32) on bin/*.exe, another process locks the file — close all instances of arqma-wallet-rpc and Tauri (`tauri dev`) before rebuilding; avoid parallel `cargo` that touches this folder while RPC is running from the same copy.
