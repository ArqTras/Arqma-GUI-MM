/**
 * Kopiuje binaria z katalogu ./bin (po rozpakowaniu w CI) do
 * rust/tauri-app/src-tauri/bin/ aby `tauri build` dołączył je jako resources.
 */
const fs = require("fs")
const path = require("path")

const root = process.cwd()
const srcDir = path.join(root, "bin")
const dstDir = path.join(root, "rust", "tauri-app", "src-tauri", "bin")

function main () {
  if (!fs.existsSync(srcDir)) {
    console.log("[copy-to-tauri-bins] brak katalogu bin — pomijam (build bez zewn. binariów).")
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
  console.log(`[copy-to-tauri-bins] skopiowano ${n} plik(ów) do ${dstDir}`)
}

main()
