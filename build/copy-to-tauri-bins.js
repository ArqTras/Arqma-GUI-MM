/**
 * Copy **arqmad** only from ./bin (after CI/download extract) into rust/tauri-app/src-tauri/bin/
 * so `tauri build` bundles the daemon as a resource (not the whole upstream archive).
 */
const fs = require("fs")
const path = require("path")

/** Repository root (this file lives in `<root>/build/`). Works regardless of `process.cwd()`. */
const root = path.resolve(__dirname, "..")
const srcDir = path.join(root, "bin")
const dstDir = path.join(root, "rust", "tauri-app", "src-tauri", "bin")

function daemonBasenames () {
  if (process.platform === "win32") {
    return ["arqmad.exe"]
  }
  return ["arqmad"]
}

function main () {
  if (!fs.existsSync(srcDir)) {
    console.log("[copy-to-tauri-bins] no ./bin directory — skipping (build without external binaries).")
    return
  }
  fs.mkdirSync(dstDir, { recursive: true })
  const allowed = new Set(daemonBasenames())
  const names = fs.readdirSync(srcDir)
  let n = 0
  for (const name of names) {
    if (!allowed.has(name)) {
      continue
    }
    const s = path.join(srcDir, name)
    if (!fs.statSync(s).isFile()) {
      continue
    }
    fs.copyFileSync(s, path.join(dstDir, name))
    n++
  }
  if (n === 0) {
    console.log(
      `[copy-to-tauri-bins] no matching daemon in ./bin (expected ${[...allowed].join(", ")}) — skipping`,
    )
    return
  }
  console.log(`[copy-to-tauri-bins] copied ${n} file(s) (arqmad only) to ${dstDir}`)
}

main()
