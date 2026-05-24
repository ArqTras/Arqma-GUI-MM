#!/usr/bin/env node
/**
 * Force Cargo output to the workspace `rust/target` (overrides e.g. agent/sandbox
 * CARGO_TARGET_DIR). The script lives in `rust/tauri-app/scripts/`.
 */
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { dirname, join, resolve, delimiter as pathDelimiter } from "node:path"

const __dirname = dirname(fileURLToPath(import.meta.url))
const tauriAppRoot = resolve(__dirname, "..")
const rustTarget = resolve(tauriAppRoot, "..", "target")
process.env.CARGO_TARGET_DIR = rustTarget
const localBin = join(tauriAppRoot, "node_modules", ".bin")
process.env.PATH = `${localBin}${pathDelimiter}${process.env.PATH || ""}`

const rest = process.argv.slice(2)
if (rest.length === 0) {
  console.error("with-rust-target: missing command (e.g. tauri build)")
  process.exit(1)
}

/** Run Cargo from `src-tauri/` (needed for `cargo tauri build` on any OS); strip this flag before spawn. */
const cwdTauriSrcIdx = rest.indexOf("--cwd-tauri-src")
let cwd = tauriAppRoot
if (cwdTauriSrcIdx !== -1) {
  cwd = join(tauriAppRoot, "src-tauri")
  rest.splice(cwdTauriSrcIdx, 1)
}
if (rest.length === 0) {
  console.error("with-rust-target: missing command after --cwd-tauri-src")
  process.exit(1)
}

// Full workspace `lto = true` + huge MinGW static archives can trigger unresolved
// libstdc++ symbols (`__real___cxa_throw`) at the final GNU ld step. Thin LTO keeps most
// Rust optimizations without that edge case. Override: set CARGO_PROFILE_RELEASE_LTO
// yourself (e.g. `false` or `fat`).
const joined = rest.join(" ")
if (/\bx86_64-pc-windows-gnu\b/.test(joined) && process.env.CARGO_PROFILE_RELEASE_LTO === undefined) {
  process.env.CARGO_PROFILE_RELEASE_LTO = "thin"
}

// Win: `spawnSync('tauri', …)` ignores PATHEXT / .cmd shims; EINVAL on direct *.cmd spawn.
const r = spawnSync(rest[0], rest.slice(1), {
  stdio: "inherit",
  env: process.env,
  cwd,
  shell: process.platform === "win32",
})
process.exit(r.status ?? 1)
