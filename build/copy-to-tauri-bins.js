/**
 * Copy binaries from ./bin (after CI extract) into rust/tauri-app/src-tauri/bin/
 * so `tauri build` bundles them as resources.
 */
const fs = require("fs")
const path = require("path")

/** Repository root (this file lives in `<root>/build/`). Works regardless of `process.cwd()`. */
const root = path.resolve(__dirname, "..")
const srcDir = path.join(root, "bin")
const dstDir = path.join(root, "rust", "tauri-app", "src-tauri", "bin")

function main () {
  if (!fs.existsSync(srcDir)) {
    console.log("[copy-to-tauri-bins] no ./bin directory — skipping (build without external binaries).")
    return
  }
  fs.mkdirSync(dstDir, { recursive: true })
  const names = fs.readdirSync(srcDir)
  let n = 0
  for (const name of names) {
    const s = path.join(srcDir, name)
    if (!fs.statSync(s).isFile()) {
      continue
    }
    fs.copyFileSync(s, path.join(dstDir, name))
    n++
  }
  console.log(`[copy-to-tauri-bins] copied ${n} file(s) to ${dstDir}`)
}

main()
