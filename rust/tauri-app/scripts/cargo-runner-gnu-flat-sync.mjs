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

/** MinGW runtime + common deps next to the PE so NSIS/MSI and flat-dir sync bundle them. */
function copyMingwRuntimeDlls(gnuDir) {
  if (process.platform !== "win32") {
    return
  }
  const mingwBin =
    process.env.ARQMA_MINGW_BIN?.trim() ||
    (process.env.ARQMA_WALLET2_MSYS_ROOT?.trim()
      ? join(process.env.ARQMA_WALLET2_MSYS_ROOT.trim().replace(/[/\\]+$/, ""), "bin")
      : "")
  if (!mingwBin || !existsSync(mingwBin)) {
    console.warn(
      "cargo-runner-gnu-flat-sync: ARQMA_MINGW_BIN / ARQMA_WALLET2_MSYS_ROOT not set — skip MinGW DLL copy (bundle may miss runtime DLLs).",
    )
    return
  }
  const fixed = [
    "libstdc++-6.dll",
    "libgcc_s_seh-1.dll",
    "libwinpthread-1.dll",
    "zlib1.dll",
    "libbz2-1.dll",
    "liblzma-5.dll",
    "libzstd.dll",
    // iconv/intl sonames vary by MSYS2 revision — also pick up libiconv-*.dll / libintl-*.dll below.
    "libssp-0.dll",
    "libsqlite3-0.dll",
  ]
  let n = 0
  for (const name of fixed) {
    const src = join(mingwBin, name)
    if (existsSync(src)) {
      copyFileSync(src, join(gnuDir, name))
      n++
    }
  }
  const dynRes = [
    /^libssl-3.*\.dll$/i,
    /^libcrypto-3.*\.dll$/i,
    /^libzmq.*\.dll$/i,
    /^libsodium.*\.dll$/i,
    /^libunbound.*\.dll$/i,
    /^libicu(in|uc|dt)/i,
    /^libiconv-/i,
    /^libintl-/i,
    /^libhogweed-/i,
    /^libnettle-/i,
    /^libgmp-/i,
  ]
  for (const f of readdirSync(mingwBin)) {
    if (!f.endsWith(".dll")) {
      continue
    }
    if (dynRes.some((re) => re.test(f))) {
      const src = join(mingwBin, f)
      const dst = join(gnuDir, f)
      if (!existsSync(dst)) {
        copyFileSync(src, dst)
        n++
      }
    }
  }
  console.log(`cargo-runner-gnu-flat-sync: copied ${n} MinGW runtime/helper DLL(s) -> ${gnuDir}`)
}

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

copyMingwRuntimeDlls(gnuDir)

let n = 0
for (const name of readdirSync(gnuDir)) {
  if (
    name === "arqma-wallet.exe" ||
    name === "arqma_flutter_solo_pool.exe" ||
    name.endsWith(".dll")
  ) {
    copyFileSync(join(gnuDir, name), join(flatDir, name))
    n++
  }
}
console.log(
  `cargo-runner-gnu-flat-sync: copied ${n} artifact(s) ${gnuDir} -> ${flatDir}`,
)

process.exit(0)
