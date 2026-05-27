/**
 * After commit: if Cursor injected Co-authored-by into HEAD, amend with a clean message.
 * Set STRIP_TRAILERS_AMEND=1 to avoid recursion when amend runs hooks again.
 */
import fs from "fs"
import os from "os"
import path from "path"
import { execSync } from "child_process"
import { fileURLToPath } from "url"
import { stripMessage } from "./strip-cursor-commit-trailers-lib.mjs"

if (process.env.STRIP_TRAILERS_AMEND === "1") process.exit(0)

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
let raw
try {
  raw = execSync("git log -1 --format=%B", { cwd: root, encoding: "utf8" })
} catch {
  process.exit(0)
}

const next = stripMessage(raw)
if (next === raw) process.exit(0)

const tmp = path.join(os.tmpdir(), `git-commit-msg-${process.pid}.txt`)
fs.writeFileSync(tmp, next, "utf8")
try {
  execSync(`git commit --amend -F "${tmp.replace(/"/g, '\\"')}"`, {
    cwd: root,
    env: { ...process.env, STRIP_TRAILERS_AMEND: "1" },
    stdio: "inherit",
  })
} finally {
  try {
    fs.unlinkSync(tmp)
  } catch {
    /* ignore */
  }
}
