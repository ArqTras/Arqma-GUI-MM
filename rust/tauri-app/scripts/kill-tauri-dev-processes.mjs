#!/usr/bin/env node
/**
 * Stop local Arqma Tauri / wallet-rpc / Vite processes for this repo so rebuilds
 * do not fight file locks or stale daemons. Used before `tauri dev` / `tauri build`.
 */
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { dirname, join, resolve } from "node:path"

const __dirname = dirname(fileURLToPath(import.meta.url))
const tauriAppRoot = resolve(__dirname, "..")
const rustRoot = resolve(tauriAppRoot, "..")
const patterns = [
  tauriAppRoot,
  join(rustRoot, "target", "debug", "arqma-wallet"),
  join(rustRoot, "target", "debug", "bin", "arqma-wallet-rpc")
]

function killUnix () {
  for (const p of patterns) {
    spawnSync("pkill", ["-TERM", "-f", p], { stdio: "ignore" })
  }
  // `pkill -f <repo-path>` often misses `arqma-wallet-rpc` when argv is short or binary was started
  // from PATH / another tree — always signal by process name (same idea as Windows `/IM`).
  spawnSync("pkill", ["-TERM", "-x", "arqma-wallet-rpc"], { stdio: "ignore" })
  spawnSync("pkill", ["-TERM", "-x", "arqma-wallet"], { stdio: "ignore" })
  spawnSync("sleep", ["2"], { stdio: "ignore" })
  for (const p of patterns) {
    spawnSync("pkill", ["-KILL", "-f", p], { stdio: "ignore" })
  }
  spawnSync("pkill", ["-KILL", "-x", "arqma-wallet-rpc"], { stdio: "ignore" })
  spawnSync("pkill", ["-KILL", "-x", "arqma-wallet"], { stdio: "ignore" })
}

function killWin () {
  spawnSync("taskkill", ["/F", "/IM", "arqma-wallet.exe", "/T"], {
    stdio: "ignore",
    shell: true
  })
  spawnSync("taskkill", ["/F", "/IM", "arqma-wallet-rpc.exe", "/T"], {
    stdio: "ignore",
    shell: true
  })
}

if (process.platform === "win32") {
  killWin()
} else {
  killUnix()
}
process.exit(0)
