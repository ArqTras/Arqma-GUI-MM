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

const r = spawnSync(rest[0], rest.slice(1), {
  stdio: "inherit",
  env: process.env,
  cwd: tauriAppRoot
})
process.exit(r.status ?? 1)
