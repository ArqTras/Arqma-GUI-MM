/**
 * After `cargo build --release -p arqma-wallet`: duplicate the exe as "Arqma Wallet.exe"
 * (Cargo cannot emit a binary name containing spaces; installers from `tauri build` use mainBinaryName.)
 */
import { copyFileSync, existsSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const appRoot = join(__dirname, "..")
const targetRelease = join(appRoot, "..", "target", "release")
const from = join(targetRelease, "arqma-wallet.exe")
const to = join(targetRelease, "Arqma Wallet.exe")

if (process.platform !== "win32") {
  console.log("postbuild-rename-windows: skipped (not Windows).")
  process.exit(0)
}

if (!existsSync(from)) {
  console.error(`postbuild-rename-windows: missing ${from} — run: cargo build --release -p arqma-wallet (from repo rust/ or any workspace cwd).`)
  process.exit(1)
}

copyFileSync(from, to)
console.log(`postbuild-rename-windows: wrote ${to}`)
