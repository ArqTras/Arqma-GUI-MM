/**
 * prepare-commit-msg: usuwa z COMMIT_EDITMSG typowe linie dodawane przez Cursor / Anysphere.
 * Nie usuwa zwykłych Co-authored-by od ludzi (inna domena niż cursor.* / anysphere).
 */
import fs from "fs"

const path = process.argv[2]
if (!path || !fs.existsSync(path)) process.exit(0)

const raw = fs.readFileSync(path, "utf8")
const nl = raw.includes("\r\n") ? "\r\n" : "\n"
const lines = raw.split(/\r?\n/)

const dropLine = (line) => {
  const t = line.trim()
  if (/^made[-\s]*with\s*:?\s*cursor\b/i.test(t)) return true
  if (!/^co-authored-by:/i.test(t)) return false
  if (/^co-authored-by:\s*cursor\s*</i.test(t)) return true
  if (/<[^>\s]+@(cursor\.(com|ai|sh)|anysphere\.[^>\s]+)>/i.test(t)) return true
  if (/\bcursor\s+agent\b/i.test(t)) return true
  return false
}

const out = lines.filter((l) => !dropLine(l))
// Usuń nadmiarowe puste linie na końcu po wycięciu trailerów
while (out.length && out[out.length - 1] === "") out.pop()
const next = out.length ? out.join(nl) + nl : ""
if (next !== raw) fs.writeFileSync(path, next, "utf8")
