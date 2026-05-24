/**
 * After `cargo build --release -p arqma-wallet`: duplicate the exe as "Arqma-Wallet.exe"
 * (Cargo cannot emit a binary name containing spaces; installers from `tauri build` use mainBinaryName.)
 */
import { copyFileSync, existsSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const appRoot = join(__dirname, "..")
const targetDir = join(appRoot, "..", "target")
const gnuRelease = join(targetDir, "x86_64-pc-windows-gnu", "release", "arqma-wallet.exe")
const hostRelease = join(targetDir, "release", "arqma-wallet.exe")
const from = existsSync(gnuRelease) ? gnuRelease : hostRelease
const targetRelease = dirname(from)
const to = join(targetRelease, "Arqma-Wallet.exe")

if (process.platform !== "win32") {
  console.log("postbuild-rename-windows: skipped (not Windows).")
  process.exit(0)
}

if (!existsSync(from)) {
  console.error(
    `postbuild-rename-windows: missing exe — expected ${gnuRelease} or ${hostRelease}\n` +
      "Run: npm run release:win (GNU target) or cargo build --release -p arqma-wallet",
  )
  process.exit(1)
}

copyFileSync(from, to)
console.log(`postbuild-rename-windows: wrote ${to}`)
