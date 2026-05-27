/**
 * Strips Cursor / Anysphere / all Co-authored-by trailers from commit messages.
 * Used by git hooks, post-commit amend, and history rewrite (--msg-filter).
 *
 * Usage:
 *   node build/strip-cursor-commit-trailers.mjs <COMMIT_EDITMSG path>
 *   node build/strip-cursor-commit-trailers.mjs -     # stdin → stdout (filter-branch)
 */
import fs from "fs"
import { stripMessage } from "./strip-cursor-commit-trailers-lib.mjs"

const path = process.argv[2]
if (!path) process.exit(0)

let raw
if (path === "-") {
  raw = fs.readFileSync(0, "utf8")
  process.stdout.write(stripMessage(raw))
  process.exit(0)
}

if (!fs.existsSync(path)) process.exit(0)
raw = fs.readFileSync(path, "utf8")
const next = stripMessage(raw)
if (next !== raw) fs.writeFileSync(path, next, "utf8")
