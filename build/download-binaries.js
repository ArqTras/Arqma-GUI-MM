const axios = require("axios").default
const fs = require("fs-extra")
const path = require("path")
const axiosRetry = require("axios-retry").default

axiosRetry(axios, {
  retries: 5, // number of retries
  retryDelay: (retryCount) => {
    console.log(`retry attempt: ${retryCount}`)
    return retryCount * 5000 // time interval between retries
  },
  retryCondition: (error) => {
    return error.response && error.response.status === 403
  }
})

async function download () {
  const { platform, env } = process
  const repoUrl = "https://api.github.com/repos/arqma/arqma/releases/latest"
  try {
    const pwd = process.cwd()
    const downloadDir = path.join(pwd, "downloads")
    await fs.ensureDir(downloadDir)

    const headers = {
      "Content-Type": "application/json"
    }
    const token = env.ARQMA_REPO_TOKEN || env.GH_TOKEN
    if (token) {
      headers.Authorization = `token ${token}`
    }

    const { data } = await axios.get(repoUrl, { headers })
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
    // Use API asset URL so Authorization is accepted (browser_download_url redirects and can 403)
    const downloadHeaders = {
      "Accept": "application/octet-stream",
      ...(token ? { Authorization: `token ${token}` } : {})
    }
    console.log("Downloading binary: " + asset.name)
    const { data: artifact } = await axios.get(asset.url, { responseType: "stream", headers: downloadHeaders })
    const writer = fs.createWriteStream(filePath)
    artifact.pipe(writer)
    await new Promise((resolve, reject) => {
      writer.on("finish", resolve)
      writer.on("error", reject)
      artifact.on("error", reject)
    })
    console.log("Downloaded binary to: " + filePath)
  } catch (err) {
    console.error("Failed to download file: " + err)
    process.exit(1)
  }
}

download()
