"use strict"

const { platform, homedir } = require("os")
const { join } = require("path")
const fs = require("fs")

function getForWindows () {
  return join(homedir(), "AppData", "Roaming")
}

function getForMac () {
  return join(homedir(), "Library", "Application Support")
}

function getForLinux () {
  return join(homedir(), ".config")
}

function getFallback () {
  if (platform().startsWith("win")) {
    return getForWindows()
  }
  return getForLinux()
}

function getAppDataPath (app) {
  let appDataPath = process.env.APPDATA

  if (appDataPath === undefined) {
    switch (platform()) {
      case "win32":
        appDataPath = getForWindows()
        break
      case "darwin":
        appDataPath = getForMac()
        break
      case "linux":
        appDataPath = getForLinux()
        break
      default:
        appDataPath = getFallback()
    }
  }

  // Ensure the base directory exists
  try {
    if (!fs.existsSync(appDataPath)) {
      fs.mkdirSync(appDataPath, { recursive: true })
    }
  } catch (e) {
    // If creation fails, fallback to homedir
    appDataPath = homedir()
  }

  if (app === undefined) {
    return appDataPath
  }

  const normalizedAppName = appDataPath !== homedir() ? app : "." + app
  const fullPath = join(appDataPath, normalizedAppName)

  // Ensure the app directory exists
  try {
    if (!fs.existsSync(fullPath)) {
      fs.mkdirSync(fullPath, { recursive: true })
    }
  } catch (e) {
    // If creation fails, fallback to appDataPath
    return appDataPath
  }

  return fullPath
}

module.exports = {
  getAppDataPath
}
