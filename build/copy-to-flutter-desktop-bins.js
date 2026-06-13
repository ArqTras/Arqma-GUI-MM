/**
 * Copy **arqmad** only from ./bin (after CI/download extract) into build/flutter-desktop-bin/
 * so Flutter desktop bundles can install the daemon next to the app executable.
 */
const fs = require("fs")
const path = require("path")

const root = path.resolve(__dirname, "..")
const srcDir = path.join(root, "bin")
const dstDir = path.join(root, "build", "flutter-desktop-bin")

function daemonBasenames () {
  if (process.platform === "win32") {
    return ["arqmad.exe"]
  }
  return ["arqmad"]
}

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

function daemonPathScore (abs, binRoot) {
  const rel = path.relative(binRoot, abs).replace(/\\/g, "/")
  let s = 0
  if (rel === "arqmad" || rel === "arqmad.exe") s += 200
  if (rel.includes(".app/")) s -= 350
  s -= rel.split("/").filter(Boolean).length
  return s
}

function findDaemonFile (allowedNames) {
  const allowed = new Set(allowedNames)
  const all = listFilesRecursive(srcDir, [])
  const hits = []
  for (const filePath of all) {
    const base = path.basename(filePath)
    if (!allowed.has(base)) {
      continue
    }
    hits.push({
      filePath,
      destName: base,
      score: daemonPathScore(filePath, srcDir)
    })
  }
  if (hits.length === 0) {
    return null
  }
  hits.sort((a, b) => b.score - a.score)
  const best = hits[0]
  if (best.score < 0) {
    return null
  }
  return { filePath: best.filePath, destName: best.destName }
}

function main () {
  if (!fs.existsSync(srcDir)) {
    console.log("[copy-to-flutter-desktop-bins] no ./bin directory — skipping.")
    return
  }
  fs.mkdirSync(dstDir, { recursive: true })
  const names = daemonBasenames()
  const hit = findDaemonFile(names)
  if (!hit) {
    console.log(
      `[copy-to-flutter-desktop-bins] no matching daemon under ./bin (expected ${names.join(", ")}) — skipping`
    )
    return
  }
  fs.copyFileSync(hit.filePath, path.join(dstDir, hit.destName))
  console.log(`[copy-to-flutter-desktop-bins] copied ${hit.destName} from ${hit.filePath} -> ${dstDir}`)
}

main()
