#!/usr/bin/env node
/**
 * Run a `.sh` script with Git Bash or MSYS `bash.exe`. Avoids PATH resolving to WSL
 * (`System32\\bash.exe`), where `set -o pipefail` often fails for CI-style scripts.
 *
 * Override: set `GIT_BASH` or `ARQMA_BASH_EXE` to the full path of `bash.exe`.
 */
import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"
import { dirname, isAbsolute, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = dirname(fileURLToPath(import.meta.url))
const appRoot = resolve(__dirname, "..")

function findBashExe (preferMsys) {
  const env = process.env.GIT_BASH ?? process.env.ARQMA_BASH_EXE
  const msysBash =
    process.env.MSYS2_ROOT &&
    join(process.env.MSYS2_ROOT.replace(/[/\\]+$/, ""), "usr", "bin", "bash.exe")
  const candidates = [
    typeof env === "string" && env.trim() ? env.trim() : null,
    preferMsys && msysBash,
    preferMsys && "C:\\msys64\\usr\\bin\\bash.exe",
    join(process.env.PROGRAMFILES ?? "C:\\Program Files", "Git", "bin", "bash.exe"),
    join(process.env["PROGRAMFILES(X86)"] ?? "C:\\Program Files (x86)", "Git", "bin", "bash.exe"),
    msysBash,
    "C:\\msys64\\usr\\bin\\bash.exe",
    "bash",
  ].filter(Boolean)

  for (const p of candidates) {
    if (p === "bash") return p
    if (existsSync(p)) return p
  }
  return "bash"
}

const scriptArg = process.argv[2]
if (!scriptArg) {
  console.error("usage: node scripts/run-bash-script.mjs <script.sh> [args...]")
  process.exit(1)
}

const scriptPath = isAbsolute(scriptArg) ? scriptArg : resolve(appRoot, scriptArg)
const rest = process.argv.slice(3)
const isMingwBuild = scriptPath.replace(/\\/g, "/").includes("build-arqma-mingw.sh")
const bash = findBashExe(isMingwBuild)

/** MinGW `cmake`/compile needs `mingw64/bin` + MSYS `usr/bin` early on PATH (especially from PowerShell). */
function envWithMingwPathFirst () {
  let mingwBin
  let usrBin
  const rw = process.env.ARQMA_WALLET2_MSYS_ROOT?.trim().replace(/[/\\]+$/, "")
  if (rw) {
    mingwBin = join(rw, "bin")
    usrBin = join(dirname(rw), "usr", "bin")
  } else if (existsSync("C:\\msys64\\mingw64\\bin\\gcc.exe")) {
    mingwBin = "C:\\msys64\\mingw64\\bin"
    usrBin = "C:\\msys64\\usr\\bin"
  } else {
    return process.env
  }
  const prepend = [mingwBin, usrBin].join(";")
  const pathKey = Object.keys(process.env).find((k) => k.toLowerCase() === "path")
  const cur = process.env[pathKey ?? "Path"] ?? ""
  const env = { ...process.env }
  env[pathKey ?? "Path"] = `${prepend};${cur}`
  return env
}

const env = isMingwBuild ? envWithMingwPathFirst() : process.env

const r = spawnSync(bash, [scriptPath, ...rest], {
  stdio: "inherit",
  cwd: appRoot,
  shell: false,
  env,
})

process.exit(r.status ?? 1)
