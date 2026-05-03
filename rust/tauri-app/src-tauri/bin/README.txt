Place arqmad.exe / arqma-wallet-rpc.exe here before `tauri build`, or copy from upstream build/release.

Windows: if Cargo build fails with "Proces nie może uzyskać dostępu..." (Win32 os error 32) on bin/*.exe, another process locks the file — close all instances of arqma-wallet-rpc and Tauri (`tauri dev`) before rebuilding; avoid parallel `cargo` that touches this folder while RPC is running from the same copy.
