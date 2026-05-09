#!/usr/bin/env node
/**
 * Tauri `mainBinaryName` expects the main exe under `target/<profile>/`, but
 * `cargo build --target x86_64-pc-windows-gnu` writes to
 * `target/x86_64-pc-windows-gnu/<profile>/`. Use as `tauri build --runner`:
 *
 *   node ./scripts/cargo-runner-gnu-flat-sync.mjs
 *
 * After a successful GNU-target build, copy exe + dlls into the flat profile dir.
 */
import { spawnSync } from "node:child_process"
import { copyFileSync, existsSync, mkdirSync, readdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const cargoArgs = process.argv.slice(2)

function cargoBin() {
  return process.env.CARGO || "cargo"
}

function profileFromArgs(args) {
  const pi = args.indexOf("--profile")
  if (pi !== -1 && args[pi + 1]) {
    return args[pi + 1]
  }
  if (args.includes("--release")) {
    return "release"
  }
  if (args.includes("--debug") || args.includes("-d")) {
    return "debug"
  }
  return "release"
}

function targetTripleFromArgs(args) {
  const ti = args.indexOf("--target")
  if (ti !== -1 && args[ti + 1]) {
    return args[ti + 1]
  }
  return null
}

const rustRoot = join(__dirname, "..", "..")
const targetRoot = process.env.CARGO_TARGET_DIR || join(rustRoot, "target")

const r = spawnSync(cargoBin(), cargoArgs, {
  stdio: "inherit",
  env: process.env,
  shell: process.platform === "win32",
})
const code = r.status ?? 1
if (code !== 0) {
  process.exit(code)
}

const triple = targetTripleFromArgs(cargoArgs)
if (triple !== "x86_64-pc-windows-gnu") {
  process.exit(0)
}

const profile = profileFromArgs(cargoArgs)
const gnuDir = join(targetRoot, triple, profile)
const flatDir = join(targetRoot, profile)

if (!existsSync(gnuDir)) {
  console.warn(`cargo-runner-gnu-flat-sync: missing ${gnuDir}, skip sync`)
  process.exit(0)
}

mkdirSync(flatDir, { recursive: true })

let n = 0
for (const name of readdirSync(gnuDir)) {
  if (name === "arqma-wallet.exe" || name.endsWith(".dll")) {
    copyFileSync(join(gnuDir, name), join(flatDir, name))
    n++
  }
}
console.log(
  `cargo-runner-gnu-flat-sync: copied ${n} artifact(s) ${gnuDir} -> ${flatDir}`,
)

process.exit(0)
