/** Shared trailer stripping for commit hooks and history rewrite. */
export function stripMessage(raw) {
  const nl = raw.includes("\r\n") ? "\r\n" : "\n"
  const lines = raw.split(/\r?\n/)

  const dropLine = (line) => {
    const t = line.trim()
    if (/^co-authored-by:/i.test(t)) return true
    if (/^made[-\s]*with\s*:?\s*cursor\b/i.test(t)) return true
    if (/^signed-off-by:\s*cursor\b/i.test(t)) return true
    if (/\bcursoragent@cursor\.com\b/i.test(t)) return true
    if (/\banysphere\b/i.test(t) && /^.+-by:/i.test(t)) return true
    return false
  }

  const out = lines.filter((l) => !dropLine(l))
  while (out.length && out[out.length - 1] === "") out.pop()
  return out.length ? out.join(nl) + nl : ""
}
