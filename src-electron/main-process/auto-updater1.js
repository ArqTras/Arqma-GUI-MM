import logger from "./modules/logger"
import os from "os"
import { app, autoUpdater, ipcMain, BrowserWindow } from "electron"
import fs from "fs"
import path from "path"
import { gte, gt } from "semver"
import EventEmitter from "events"
const axios = require("axios")

const eventTypes = [
  "error",
  "checking-for-update",
  "update-available",
  "update-not-available",
  "update-downloading",
  "update-downloaded",
  "before-quit-for-update"
]

const supportedPlatforms = ["darwin", "win32"]

export class FooAutoUpdater extends EventEmitter {
  constructor ({ baseUrl, owner, repo, accessToken }) {
    logger.info(`auto-updater constructor ${baseUrl}, ${owner}, ${repo}, ${accessToken}`)
    super()
    this.tempDir = this.getTempDir()
    this.platformConfig = {
      win32: {
        requiredFiles: [/Arqma.Wallet.Setup\.\d{1,}\.\d{1,}\.\d{1,}\.exe/],
        feedUrl: this.tempDir + "\\"
      },
      darwin: {
        requiredFiles: [/Arqma.Wallet.Setup\.\d{1,}\.\d{1,}\.\d{1,}\.tar\.xz/],
        feedUrl: path.join(this.tempDir, "feed.json")
      }
    }
    this.releaseIdCachePath = path.join(this.tempDir, ".cache")
    this.baseUrl = "https:/api.github.com"
    if (!!baseUrl) { this.baseUrl = baseUrl }
    this.owner = owner
    this.repo = repo
    this.accessToken = accessToken
    this.allowPrerelease = false
    this.forwardEvents = true
    this.channelName = "autoUpdater"
    this._autoUpdater = autoUpdater
    this.registerIpcListeners()
  }

  registerIpcListeners = () => {
    ipcMain.handle(`${this.channelName}.checkForUpdates`, (event) => {
      logger.info("auto-updater registerIpcListeners checkForUpdates")
      this.checkForUpdates()
      return true
    })
    ipcMain.handle(`${this.channelName}.quitAndInstall`, (event) => {
      logger.info("auto-updater registerIpcListeners quitAndInstall")
      this.quitAndInstall()
      return true
    })

    ipcMain.handle(`${this.channelName}.clearCache`, (event) => {
      logger.info("auto-updater registerIpcListeners clearCache")
      this.clearCache()
      return true
    })
  }

  /**************************************************************************************************
   *     EventEmitter Overrides
   **************************************************************************************************/

  emit = (event, args) => {
    if (!eventTypes.includes(event)) { throw new Error(`${event} is not an event that can be emitted by this class`) }
    if (this.forwardEvents) {
      BrowserWindow.getAllWindows().map((window) => {
        logger.info(`auto-updater emit ${this.channelName}, ${event}, ${JSON.stringify(args)}`)
        window.webContents.send(this.channelName, { event, data: args })
      })
    }

    if (!args) {
      return super.emit(event)
    } else if (Array.isArray(args)) {
      return super.emit(event, ...args)
    } else {
      return super.emit(event, args)
    }
  }

  on = (event, listener) => {
    if (typeof listener !== "function") throw new Error("Listener must be a function")
    if (!eventTypes.includes(event)) { throw new Error(`${event} is not an event emitted by this class`) }

    super.on(event, listener)
    return this
  }

  once = (event, listener) => {
    if (typeof listener !== "function") throw new Error("Listener must be a function")
    if (!eventTypes.includes(event)) { throw new Error(`${event} is not an event emitted by this class`) }

    return super.once(event, listener)
  }

  /**************************************************************************************************
   *     Internal Methods
   **************************************************************************************************/
  _emitError = (error) => {
    this.emit("error", error)
    throw error
  }

  _getLatestRelease = async () => {
    try {
      logger.info("auto-updater _getLatestRelease")
      const options = {}
      if (!!this.accessToken) { options.headers = { Authorization: `token ${this.accessToken}` } }
      if (this.allowPrerelease) {
        const response = await axios.get(
                `${this.baseUrl}/repos/${this.owner}/${this.repo}/releases?per_page=100`, options
        )
        const releases = response

        const filtered = releases.filter((release) => !release.prerelease)
        if (filtered.length === 0) {
          throw new Error("No production releases found")
        } else {
          return filtered[0]
        }
      } else {
        const response = await axios.get(
          `${this.baseUrl}/repos/${this.owner}/${this.repo}/releases/latest`, options
        )
        return response.data
      }
    } catch (error) {
      return null
    }
  }

  // Downloads all required update files for the current platform
  _downloadUpdateFiles = async (release, platform) => {
    logger.info("auto-updater _downloadUpdateFiles")
    const assets = this.findRequiredReleaseAssets(release.assets, platform)

    // Set variables to track download progress, including calculating the total download size
    const totalSize = assets.reduce((prev, asset) => (prev += asset.size), 0)
    let downloaded = 0

    // Download the files
    for await (const file of assets) {
      const outputPath = path.join(this.tempDir, file.name)
      const assetDownloadUrl = file.browser_download_url // file.url // `${this.baseUrl}/repos/${this.owner}/${this.repo}/releases/assets/${file.id}`
      await this._downloadUpdateFile(assetDownloadUrl, outputPath, (event) => {
        downloaded += event.loaded

        this.emit("update-downloading", {
          size: totalSize,
          progress: downloaded,
          percent: Math.round((downloaded * 100) / totalSize)
        })
      })
    }
    // Write a cache file containing the release ID
    fs.writeFileSync(this.releaseIdCachePath, release.id.toString(), { encoding: "utf-8" })
    logger.info("auto-updater _downloadUpdateFiles, Done downloading update files")
  }

  // Downloads a single file
  _downloadUpdateFile = async (
    assetUrl,
    outputPath,
    onProgressEvent
  ) => {
    logger.info("auto-updater _downloadUpdateFile")
    // eslint-disable-next-line no-async-promise-executor
    return new Promise(async (resolve, reject) => {
      const { data } = await axios.get(assetUrl, {
        headers: {
          // ...{ Authorization: `token ${this.accessToken}` },
          Accept: "application/octet-stream"
        },
        responseType: "stream"
      })

      const writer = fs.createWriteStream(outputPath)

      // Emit a progress event when a chunk is downloaded
      data.on("data", (chunk) => {
        onProgressEvent({ loaded: chunk.length })
      })

      // Pipe data into a writer to save it to the disk rather than keeping it in memory
      data.pipe(writer)

      return data.on("end", () => {
        return resolve(true)
      })
    })
  }

  // Preps the default electron autoUpdater to install the update
  _loadElectronAutoUpdater = (release, platform) => {
    try {
      logger.info("auto-updater _loadElectronAutoUpdater")
      this.emit("update-downloaded", {
        releaseName: release.name,
        releaseNotes: release.body || "",
        releaseDate: new Date(release.published_at),
        updateUrl: release.html_url
      })
      if (process.env.NODE_ENV !== "development") {
        logger.info(`auto-updater _loadElectronAutoUpdater ${platform.feedUrl}`)
        this.autoUpdater.setFeedURL({ url: platform.feedUrl })
      }
    } catch (error) {
      logger.error(JSON.stringify(error))
    }
  }

  // Uses electron autoUpdater to install the downloaded update
  _installDownloadedUpdate = () => {
    logger.info("auto-updater _installDownloadedUpdate")
    if (process.env.NODE_ENV !== "development") {
      this.autoUpdater.checkForUpdates()
    } else {
      logger.info("auto-updater _installDownloadedUpdate, Cannot install an update while running in dev mode.")
    }
  }

  /**************************************************************************************************
   *     autoUpdater Overrides
   **************************************************************************************************/

  checkForUpdates = async () => {
    try {
      logger.info("auto-updater checkForUpdates")
      this.emit("checking-for-update")

      logger.info("auto-updater findRequiredReleaseAssests")
      const platform = os.platform()
      if (!supportedPlatforms.includes(platform)) { throw new Error(`Platform ${platform} is not yet supported`) }

      const supportedPlatform = this.platformConfig[platform]

      // Find the latest release
      const latestRelease = await this._getLatestRelease()
      if (!latestRelease) { return }
      const latestReleaseVersion = latestRelease.tag_name
      const releaseId = latestRelease.id
      const currentVersion = process.env.VERSION// app.getVersion()
      const cachedReleaseId = this.getCachedReleaseId()

      // If the current app version is greater than or equal to the latest release, there is no update available
      if (gte(currentVersion, latestReleaseVersion)) this.emit("update-not-available")
      // If the latest release is a higher version than the installed version
      else if (gt(latestReleaseVersion, currentVersion)) {
        this.emit("update-available")

        // If there is a cached update and the ID is the same as the latest release ID
        // then we have already downloaded the latest update.
        if (cachedReleaseId !== releaseId) {
          await this._downloadUpdateFiles(latestRelease, supportedPlatform)
        }
        // Load the built in electron auto updater with the files we generated
        this._loadElectronAutoUpdater(latestRelease, supportedPlatform)
        // Use the built in electron auto updater to install the update
        this._installDownloadedUpdate()
      } else {
        // If we get here, there is a bug in the above logic.
        logger.eror(`auto-updater ${currentVersion}, ${latestReleaseVersion}, ${latestRelease}, ${releaseId}, ${cachedReleaseId}`)
        throw new Error(
          "Error in cache and release semver comparison. This is not a bug in your code, this is a problem with the library."
        )
      }
    } catch (e) {
      this._emitError(e)
    }
  }

  quitAndInstall = () => {
    try {
      logger.info("auto-updater quitAndInstall")
      this.autoUpdater.quitAndInstall()
    } catch (e) {
      this._emitError(e)
    }
  }

  clearCache = () => {
    logger.info("auto-updater clearCache")
    try {
      fs.rmSync(this.tempDir, { recursive: true, force: true })
      if (fs.existsSync(this.tempDir)) throw new Error("Failed to clear temp directory")
      this.getTempDir()
      logger.info("auto-updater clearCache, Done clearing autoUpdater cache")
      this.emit("update-not-available")
    } catch (e) {
      this._emitError(e)
    }
  }

  findRequiredReleaseAssets = (assets, platform) => {
    logger.info("auto-updater findRequiredReleaseAssets")

    return platform.requiredFiles.map((filePattern) => {
      const match = assets.find((asset) => asset.name.match(filePattern))
      if (!match) {
        throw new Error(
          `Release is missing a required update file for current platform (${platform})`
        )
      } else return match
    })
  }

  getTempDir = () => {
    logger.info("auto-updater getTempDir")
    const tempDirPath = path.join(app.getPath("temp"), app.getName())
    // Create the temp dir
    if (!fs.existsSync(tempDirPath)) fs.mkdirSync(tempDirPath)
    return tempDirPath
  }

  getCachedReleaseId = () => {
    logger.info("auto-updater getCachedReleaseId")
    if (fs.existsSync(this.releaseIdCachePath)) {
      return parseInt(fs.readFileSync(this.releaseIdCachePath, { encoding: "utf-8" }))
    } else {
      return null
    }
  }
}
