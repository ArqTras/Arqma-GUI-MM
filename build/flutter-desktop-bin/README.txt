Place **arqmad.exe** (Windows) or **arqmad** (Unix) here before `flutter build`, or run from repo root:

  node build/copy-to-flutter-desktop-bins.js

after `./bin` contains **arqmad** from download/extract (script copies **arqmad only**). Do not put **arqma-wallet-rpc** in this directory.

**Flutter desktop:** `flutter build macos|linux|windows` installs **arqmad** and **arqma_flutter_solo_pool** from this folder into the app bundle (`Contents/Resources/bin` on macOS, `bin/` next to the exe on Linux/Windows). Prebuilt solo pool sidecar: `bash build/ci/fetch-arqma-wallet-solo-pool-release-linux.sh` (ArqTras/FFI). Override paths at runtime with `ARQMA_DAEMON`, `ARQMA_FLUTTER_SOLO_POOL` if needed.

Legacy Electron/Tauri tree: branch **`outdated`** on this repository.
