/**
 * Installs commit-msg / prepare-commit-msg hooks into .git/hooks (no husky binary required).
 * Run via `npm run prepare` so Co-authored-by / Cursor trailers are stripped on every commit.
 */
import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"
import { execSync } from "child_process"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const stripScript = path.join(root, "build", "strip-cursor-commit-trailers.mjs")
const gitDir = execSync("git rev-parse --git-dir", { cwd: root, encoding: "utf8" }).trim()
const hooksDir = path.resolve(root, gitDir, "hooks")

const hookBody = (name) => `#!/bin/sh
# ${name} — strip Co-authored-by / Cursor trailers (ArqTras-only commits)
node "${stripScript.replace(/\\/g, "/")}" "$1"
`

const postCommitBody = `#!/bin/sh
# post-commit — amend if Cursor injected Co-authored-by after hooks ran
node "${stripScript.replace(/\\/g, "/").replace("strip-cursor-commit-trailers.mjs", "post-commit-strip-trailers.mjs")}"
`

for (const name of ["prepare-commit-msg", "commit-msg"]) {
  const target = path.join(hooksDir, name)
  fs.mkdirSync(hooksDir, { recursive: true })
  fs.writeFileSync(target, hookBody(name), "utf8")
  try {
    fs.chmodSync(target, 0o755)
  } catch {
    /* Windows: git runs hooks via sh */
  }
}

const postCommit = path.join(hooksDir, "post-commit")
fs.writeFileSync(postCommit, postCommitBody, "utf8")
try {
  fs.chmodSync(postCommit, 0o755)
} catch {
  /* Windows */
}

console.log("git hooks installed:", hooksDir)
