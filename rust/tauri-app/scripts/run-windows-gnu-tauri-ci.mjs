#!/usr/bin/env node
/**
 * Windows-only: MSYS2 MinGW + `x86_64-pc-windows-gnu` Tauri CI.
 * Linux/macOS: use `npm run ci:tauri:native` (this script exits with a message if run elsewhere).
 *
 * Vite/npm must not see MSYS MinGW *before* MSVC Node (native addons / Vite crash).
 * The Cargo step must not put MinGW *before* MSVC either: host `build.rs` crates (e.g. `vswhom-sys`) use the `cc`
 * crate — if `g++.exe` wins first, objects are GCC-style but MSVC `link.exe` still links them → LNK2001.
 * Append MinGW at the **end** of PATH and set `CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER` so the GNU target uses
 * the MinGW linker. Tauri is invoked via npm `@tauri-apps/cli` (`tauri build`, not `cargo tauri`).
 */
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import { dirname, join, resolve, delimiter as pathDelimiter } from "node:path"

const __dirname = dirname(fileURLToPath(import.meta.url))

if (process.platform !== "win32") {
  console.error(
    "run-windows-gnu-tauri-ci: Windows only (MSYS2 + x86_64-pc-windows-gnu). On Linux/macOS use: npm run ci:tauri:native",
  )
  process.exit(1)
}

const tauriAppRoot = resolve(__dirname, "..")
const localBin = join(tauriAppRoot, "node_modules", ".bin")
const msysRoot = (process.env.MSYS2_ROOT || process.env.ARQMA_MSYS2_ROOT || "C:\\msys64").replace(/[/\\]+$/, "")
const mingwRoot = join(msysRoot, "mingw64")
const mingwBin = join(mingwRoot, "bin")
const usrBin = join(msysRoot, "usr", "bin")

function stripMsysFromPath(pathVal) {
  return (pathVal || "")
    .split(pathDelimiter)
    .filter((p) => p && !/[\\/]msys64[\\/]/i.test(p))
    .join(pathDelimiter)
}

function withLocalBin(pathVal) {
  return `${localBin}${pathDelimiter}${pathVal}`
}

function runNpmStep(scriptName, pathEnv) {
  const env = {
    ...process.env,
    PATH: withLocalBin(pathEnv),
    CI: process.env.CI || "true",
  }
  const r = spawnSync("npm", ["run", scriptName], {
    stdio: "inherit",
    cwd: tauriAppRoot,
    env,
    shell: process.platform === "win32",
  })
  const code = r.status ?? 1
  if (code !== 0) {
    process.exit(code)
  }
}

const pathNoMsys = stripMsysFromPath(process.env.PATH || "")
/** MinGW last: MSVC host build scripts; GNU link via `CARGO_TARGET_*_LINKER`. */
const pathMsysForCargo = `${pathNoMsys}${pathDelimiter}${mingwBin}${pathDelimiter}${usrBin}`
const gnuLinker = join(mingwBin, "x86_64-w64-mingw32-gcc.exe")

const configMerge = join(tauriAppRoot, "scripts", "tauri-ci-gnu-no-frontend.json").replace(/\\/g, "/")

runNpmStep("copy:bins", pathNoMsys)
runNpmStep("build", pathNoMsys)
runNpmStep("kill:dev", pathNoMsys)

const r = spawnSync(
  process.execPath,
  [
    join(tauriAppRoot, "scripts", "with-rust-target.mjs"),
    "tauri",
    "build",
    "--ci",
    "--config",
    configMerge,
    "--runner",
    "../scripts/cargo-runner-gnu-flat-sync.cmd",
    "--",
    "--target",
    "x86_64-pc-windows-gnu",
  ],
  {
    stdio: "inherit",
    cwd: tauriAppRoot,
    env: (() => {
      const e = { ...process.env, PATH: withLocalBin(pathMsysForCargo), CI: process.env.CI || "true" }
      e.CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = gnuLinker
      e.ARQMA_WALLET2_MSYS_ROOT = mingwRoot
      e.ARQMA_MINGW_BIN = mingwBin
      if (!e.ARQMA_WALLET2_UPSTREAM_DIR) {
        e.ARQMA_WALLET2_UPSTREAM_DIR = join(tauriAppRoot, "..", "arqma-rpc-upstream")
      }
      // Host build.rs (e.g. vswhom-sys) must use MSVC `cl`+`link`, not a stray MSYS `g++` from CC/CXX.
      delete e.CC
      delete e.CXX
      delete e.CFLAGS
      delete e.CXXFLAGS
      delete e.HOST_CC
      delete e.HOST_CXX
      return e
    })(),
    shell: process.platform === "win32",
  },
)
process.exit(r.status ?? 1)
