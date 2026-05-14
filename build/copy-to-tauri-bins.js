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

/** macOS `unzip` often leaves `arqmad` nested under `./bin/<subdir>/...`; Linux tar can too. */
function listFilesRecursive (dir, acc) {
  if (!fs.existsSync(dir)) {
    return acc
  }
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name)
    const st = fs.statSync(full)
    if (st.isDirectory()) {
      listFilesRecursive(full, acc)
    } else if (st.isFile()) {
      acc.push(full)
    }
  }
  return acc
}

function findDaemonFile (allowedNames) {
  const allowed = new Set(allowedNames)
  const all = listFilesRecursive(srcDir, [])
  for (const filePath of all) {
    const base = path.basename(filePath)
    if (allowed.has(base)) {
      return { filePath, destName: base }
    }
  }
  return null
}

function main () {
  if (!fs.existsSync(srcDir)) {
    console.log("[copy-to-tauri-bins] no ./bin directory — skipping (build without external binaries).")
    return
  }
  fs.mkdirSync(dstDir, { recursive: true })
  const names = daemonBasenames()
  const hit = findDaemonFile(names)
  if (!hit) {
    console.log(
      `[copy-to-tauri-bins] no matching daemon under ./bin (expected ${names.join(", ")} anywhere under ./bin) — skipping`
    )
    return
  }
  fs.copyFileSync(hit.filePath, path.join(dstDir, hit.destName))
  console.log(`[copy-to-tauri-bins] copied ${hit.destName} from ${hit.filePath} -> ${dstDir}`)
}

main()
