/**
 * Recursively collect dot-paths for string leaves and object branches.
 * @param {unknown} obj
 * @param {string} prefix
 * @returns {Map<string, string>} path -> leaf value (only for string/number leaves as JSON allows)
 */
function collectStringLeaves (obj, prefix = "") {
  const out = new Map()
  if (obj === null || obj === undefined) return out
  if (typeof obj !== "object") {
    out.set(prefix || "(root)", String(obj))
    return out
  }
  if (Array.isArray(obj)) {
    obj.forEach((v, i) => {
      const p = prefix ? `${prefix}.${i}` : String(i)
      for (const [k, v2] of collectStringLeaves(v, p)) out.set(k, v2)
    })
    return out
  }
  for (const [k, v] of Object.entries(obj)) {
    const p = prefix ? `${prefix}.${k}` : k
    if (typeof v === "object" && v !== null && !Array.isArray(v)) {
      for (const [k2, v2] of collectStringLeaves(v, p)) out.set(k2, v2)
    } else if (typeof v === "string" || typeof v === "number" || typeof v === "boolean") {
      out.set(p, typeof v === "string" ? v : JSON.stringify(v))
    } else if (Array.isArray(v)) {
      for (const [k2, v2] of collectStringLeaves(v, p)) out.set(k2, v2)
    }
  }
  return out
}

function setDeep (root, path, value) {
  const parts = path.split(".")
  let cur = root
  for (let i = 0; i < parts.length - 1; i++) {
    const p = parts[i]
    if (cur[p] === undefined || typeof cur[p] !== "object" || Array.isArray(cur[p])) {
      cur[p] = {}
    }
    cur = cur[p]
  }
  cur[parts[parts.length - 1]] = value
}

function getDeep (root, path) {
  const parts = path.split(".")
  let cur = root
  for (const p of parts) {
    if (cur === undefined || cur === null) return undefined
    cur = cur[p]
  }
  return cur
}

import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const dirs = [
  { name: "tauri-app", path: path.join(__dirname, "..", "src", "locales") },
  { name: "src", path: path.join(__dirname, "..", "..", "..", "src", "locales") }
]

const fullReport = {}

for (const { name, path: localesDir } of dirs) {
  if (!fs.existsSync(localesDir)) continue
  const files = fs.readdirSync(localesDir).filter((f) => f.endsWith(".json")).sort()
  const enPath = path.join(localesDir, "en-US.json")
  const enRaw = JSON.parse(fs.readFileSync(enPath, "utf8"))
  const enLeaves = collectStringLeaves(enRaw)

  const report = { missingByFile: {}, extraByFile: {}, counts: {} }

  for (const f of files) {
    if (f === "en-US.json") continue
    const p = path.join(localesDir, f)
    const loc = JSON.parse(fs.readFileSync(p, "utf8"))
    const locLeaves = collectStringLeaves(loc)
    const missing = []
    const extra = []
    for (const key of enLeaves.keys()) {
      if (!locLeaves.has(key)) missing.push(key)
    }
    for (const key of locLeaves.keys()) {
      if (!enLeaves.has(key)) extra.push(key)
    }
    report.missingByFile[f] = missing
    report.extraByFile[f] = extra
    report.counts[f] = { missing: missing.length, extra: extra.length }
  }
  fullReport[name] = report
}

console.log(JSON.stringify(fullReport, null, 2))
