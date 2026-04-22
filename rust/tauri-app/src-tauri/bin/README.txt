Tauri bundle folder "bin" (served as resource_dir/bin).

Before building a **release** installer, place official Arqma binaries here so the backend can spawn them:
  - Windows: arqmad.exe, arqma-wallet-rpc.exe
  - Linux / macOS: arqmad, arqma-wallet-rpc (chmod +x)

Do not commit executables to git (they are listed in .gitignore).
Source: official Arqma repository builds / project CI artifacts.
