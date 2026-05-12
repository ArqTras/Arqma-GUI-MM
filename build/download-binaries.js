/**
 * Download Arqma **static release** binaries from GitHub Releases (`arqma/arqma` latest by default).
 * Prefers full bundles over `build-depends-*` dependency archives when both exist.
 * Uses Node 20+ only (fetch, fs) — no axios/fs-extra so CI can run this before npm install.
 */
const { createWriteStream } = require("fs")
const fsp = require("fs/promises")
const path = require("path")
const { pipeline } = require("stream/promises")
const { Readable } = require("stream")

async function fetchWithRetry403 (url, init = {}, maxRetries = 5) {
  let lastRes = null
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    lastRes = await fetch(url, init)
    if (lastRes.status !== 403) {
      return lastRes
    }
    if (attempt < maxRetries) {
      console.log(`retry attempt: ${attempt}`)
      await new Promise((resolve) => setTimeout(resolve, attempt * 5000))
    }
  }
  return lastRes
}

/** Prefer real release bundles; penalize CMake dependency-only archives. */
function scoreAssetName (name) {
  const n = (name || "").toLowerCase()
  let s = 0
  if (n.includes("build-depends")) { s -= 80 }
  if (n.includes("arqmad") || /daemon|cli|binaries|static|release/.test(n)) { s += 40 }
  if (n.endsWith(".zip") || n.endsWith(".gz") || n.endsWith(".tar.gz") || n.endsWith(".tgz")) { s += 5 }
  return s
}

function matchesPlatformAsset (name, browserUrl, platform, arch) {
  const blob = `${name || ""} ${browserUrl || ""}`.toLowerCase()
  if (platform === "darwin") {
    if (arch === "arm64") {
      return (/arm64|aarch64|apple|silicon|m-series/.test(blob) && /mac|darwin|osx/.test(blob)) ||
        blob.includes("build-depends-macOS-arm64")
    }
    return (/x64|x86_64|amd64/.test(blob) && /mac|darwin|osx/.test(blob)) ||
      blob.includes("osx-x64") || blob.includes("macos-x64")
  }
  if (platform === "win32") {
    if (/linux|darwin|osx|mac|ubuntu|\.tar\.gz|\.dmg|\.AppImage/.test(blob)) {
      return false
    }
    return /win64|windows|w64|mingw|msvc|\.exe/.test(blob)
  }
  if (/darwin|osx|mac|win64|windows|mingw|msvc/.test(blob)) {
    return false
  }
  return /linux|x86_64|amd64|ubuntu|gnu|debian|fedora|appimage|\.tar\.gz|\.tar\.xz|\.gz|\.tgz/.test(blob)
}

function pickAsset (assets, platform, arch) {
  const list = assets || []
  const matched = list.filter(a =>
    matchesPlatformAsset(a.name, a.browser_download_url, platform, arch)
  )
  if (matched.length === 0) {
    return null
  }
  matched.sort((a, b) =>
    scoreAssetName(b.name) - scoreAssetName(a.name)
  )
  return matched[0]
}

/** Legacy fallback (older release layouts). */
function legacyPickAsset (assets, platform) {
  return (assets || []).find(a => {
    const url = a.browser_download_url || ""
    if (platform === "darwin") {
      return process.arch === "arm64"
        ? url.includes("build-depends-macOS-arm64")
        : url.includes("osx-x64") || url.includes("macOS-x64")
    }
    if (platform === "win32") {
      return url.includes("win64")
    }
    return url.includes("build-depends-x86_64-linux")
  })
}

function localDownloadBasename (assetName, browserDownloadUrl) {
  const n = (assetName || "").toLowerCase()
  if (n.endsWith(".tar.xz")) return "latest.tar.xz"
  if (n.endsWith(".txz")) return "latest.txz"
  if (n.endsWith(".tar.gz")) return "latest.tar.gz"
  if (n.endsWith(".tgz")) return "latest.tgz"
  if (n.endsWith(".zip")) return "latest.zip"
  const u = (browserDownloadUrl || "").toLowerCase()
  if (u.includes(".tar.xz")) return "latest.tar.xz"
  if (u.includes(".tar.gz")) return "latest.tar.gz"
  const ext = path.extname(assetName || "") || path.extname(browserDownloadUrl || "") || ".bin"
  return "latest" + ext
}

async function download () {
  const { platform, env } = process
  const repo = (env.ARQMA_GITHUB_RELEASE_REPO || "arqma/arqma").trim()
  const repoUrl = `https://api.github.com/repos/${repo}/releases/latest`
  try {
    const pwd = process.cwd()
    const downloadDir = path.join(pwd, "downloads")
    await fsp.mkdir(downloadDir, { recursive: true })

    const headers = {
      "Content-Type": "application/json"
    }
    if (env.GH_TOKEN) {
      headers.Authorization = `token ${env.GH_TOKEN}`
    }

    const metaRes = await fetchWithRetry403(repoUrl, { headers })
    if (!metaRes.ok) {
      throw new Error(`GitHub API: ${metaRes.status} ${metaRes.statusText}`)
    }
    const data = await metaRes.json()

    let asset = pickAsset(data.assets || [], platform, process.arch)
    if (!asset) {
      asset = legacyPickAsset(data.assets || [], platform)
    }

    if (!asset) {
      throw new Error("Download url not found for " + process.platform + "/" + process.arch)
    }
    // GitHub asset URLs may omit multi-suffix names (e.g. `.tar.xz` → `path.extname` is `.xz`).
    // CI expects stable names like `latest.tar.xz` / `latest.zip` for extract steps.
    const filePath = path.join(downloadDir, localDownloadBasename(asset.name, asset.browser_download_url))
    const downloadHeaders = {
      Accept: "application/octet-stream",
      ...(env.GH_TOKEN ? { Authorization: `token ${env.GH_TOKEN}` } : {})
    }
    console.log("Downloading release asset: " + asset.name)
    const binRes = await fetchWithRetry403(asset.url, { headers: downloadHeaders })
    if (!binRes.ok) {
      throw new Error(`Download: ${binRes.status} ${binRes.statusText}`)
    }
    if (!binRes.body) {
      throw new Error("Download: empty body")
    }
    const nodeReadable = Readable.fromWeb(binRes.body)
    await pipeline(nodeReadable, createWriteStream(filePath))
    console.log("Downloaded binary to: " + filePath)
  } catch (err) {
    console.error("Failed to download file: " + err)
    process.exit(1)
  }
}

download()
