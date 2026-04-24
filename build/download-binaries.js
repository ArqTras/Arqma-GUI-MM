/**
 * Download Arqma binaries from GitHub Releases (Arqma API).
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

async function download () {
  const { platform, env } = process
  const repoUrl = "https://api.github.com/repos/arqma/arqma/releases/latest"
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

    const asset = (data.assets || []).find(a => {
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

    if (!asset) { throw new Error("Download url not found for " + process.platform + "/" + process.arch) }
    const extension = path.extname(asset.browser_download_url)
    const filePath = path.join(downloadDir, "latest" + extension)
    const downloadHeaders = {
      Accept: "application/octet-stream",
      ...(env.GH_TOKEN ? { Authorization: `token ${env.GH_TOKEN}` } : {})
    }
    console.log("Downloading binary: " + asset.name)
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
