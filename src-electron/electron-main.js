/* eslint-disable import/first */
import path from "path"
import { app, BrowserWindow, nativeTheme, ipcMain, Menu } from "electron"
import os from "os"
import { Backend } from "./main-process/modules/backend"
import logger from "./main-process/modules/logger"
import menuTemplate from "./main-process/menu"
import { existsSync } from "fs"
import { useIPCMainHandler } from "./ipcMainHandler"

// const { autoUpdater } = require("electron-updater")
const Store = require("electron-store")

app.disableHardwareAcceleration()

// autoUpdater.logger = logger
// autoUpdater.disableWebInstaller = true
const store = new Store()

// needed in case process is undefined under Linux
const platform = process.platform || os.platform()

try {
  if (platform === "win32" && nativeTheme.shouldUseDarkColors === true) {
    require("fs").unlinkSync(
      path.join(app.getPath("userData"), "DevTools Extensions")
    )
  }
} catch (_) {}

if (process.env.NODE_ENV !== "development") {
  global.__statics = path.join(__dirname, "statics").replace(/\\/g, "\\\\")
  global.__binDirectory = path
    .join(__dirname, "..", "bin")
    .replace(/\\/g, "\\\\")
  global.__resourceDirectory = app.getPath("userData")
    .replace(/\\/g, "\\\\")
} else {
  global.__binDirectory = path
    .join(process.cwd(), "bin")
    .replace(/\\/g, "\\\\")
  global.__resourceDirectory = process.cwd()
    .replace(/\\/g, "\\\\")
}

let mainWindow
let backend
let showConfirmClose = true
let forceQuit = false
const installUpdate = false

function createWindow () {
  /**
   * Initial window options
  */

  const windowConfig = store.get("windowConfig") || { width: 1000, height: 600, x: 50, y: 50 }

  mainWindow = new BrowserWindow({

    icon: path.resolve(__dirname, "icons/icon_512x512.png"), // tray icon
    width: windowConfig.width,
    height: windowConfig.height,
    useContentSize: true,
    x: windowConfig.x,
    y: windowConfig.y,
    webPreferences: {
      sandbox: false,
      contextIsolation: true,
      preload: path.resolve(__dirname, process.env.QUASAR_ELECTRON_PRELOAD)
    }
  })

  useIPCMainHandler(mainWindow)

  mainWindow.loadURL(process.env.APP_URL)

  if (process.env.DEBUGGING) {
    // if on DEV or Production with debug enabled
    mainWindow.webContents.openDevTools()
  } else {
    // we're on production; no access to devtools pls
    mainWindow.webContents.on("devtools-opened", () => {
      mainWindow.webContents.closeDevTools()
    })
  }

  mainWindow.on("resize", () => {
    const [width, height] = mainWindow.getSize()
    store.set("windowConfig", { width, height })
  })

  mainWindow.on("move", () => {
    const [x, y] = mainWindow.getPosition()
    store.set("windowConfig", { ...store.get("windowConfig"), x, y })
  })

  mainWindow.on("close", (e) => {
    logger.info("electron-main close")
    if (installUpdate) { return }
    if (platform === "darwin") {
      if (forceQuit) {
        forceQuit = false
        if (showConfirmClose) {
          e.preventDefault()
          mainWindow.show()
          mainWindow.webContents.send("receiveConfirmClose")
        }
        // else {
        //   e.defaultPrevented = false
        // }
      } else {
        e.preventDefault()
        mainWindow.hide()
      }
    } else {
      if (showConfirmClose) {
        e.preventDefault()
        logger.info("electron-main close sending 'receiveConfirmClose'")
        mainWindow.webContents.send("receiveConfirmClose")
      }
    // else {
    //     e.defaultPrevented = false
    //   }
    }
  })

  mainWindow.webContents.on("did-finish-load", async () => {
    backend = new Backend(mainWindow)
    await backend.init()
    logger.info("electron-main did-finish-load, backend initialized")
    mainWindow.webContents.send("receive", { event: "initialize" })
    // logger.info("electron-main did-finish-load, calling checkForUpdatesAndNotify")
    // autoUpdater.checkForUpdatesAndNotify()
  })
}

app.whenReady().then(() => {
  if (process.platform === "darwin") {
    const menu = Menu.buildFromTemplate(menuTemplate)
    Menu.setApplicationMenu(menu)
  }
  createWindow()
})

app.on("window-all-closed", () => {
  logger.info("electron-main window-all-closed")
  if (platform !== "darwin") {
    app.quit()
  }
})

app.on("activate", () => {
  logger.info("electron-main activate")
  if (mainWindow === null) {
    createWindow()
  }
})

app.on("before-quit", async () => {
  logger.info("electron-main before-quit")
  if (installUpdate) {
    return
  }
  if (process.platform === "darwin") {
    forceQuit = true
  } else {
    if (backend) {
      await backend.quit()
      backend = null
      logger.info("electron-main before-quit")
    }
  }
})

ipcMain.handle("confirmClose", (event, restart) => {
  showConfirmClose = false

  // In dev mode, this will launch a blank white screen
  //   if (restart && process.env.NODE_ENV !== "development") {
  //     app.relaunch()
  //   }

  const promise = backend ? backend.quit() : Promise.resolve()
  promise.then(() => {
    backend = null
    app.quit()
  })
})

ipcMain.handle("foo:send", async (event, message) => {
  logger.info(`electron-main foo:send ${JSON.stringify(message)}`)
  if (backend) {
    await backend.receive(message)
  }
})

ipcMain.handle("foo:isDevelopment", (event, message) => {
  logger.info(`electron-main foo:isDevelopment >>${process.env.NODE_ENV}<<`)
  const pattern = /development/i
  return pattern.test(process.env.NODE_ENV)
})

ipcMain.handle("foo:version", (event, message) => {
  logger.info("electron-main foo:version")
  return process.env.CUSTOM_VERSION
})

ipcMain.handle("foo:daemonVersion", (event, message) => {
  logger.info("electron-main foo:daemonVersion")
  backend.receive({ module: "daemon", method: "check_version" })
})

function sendStatusToWindow (text) {
  logger.info(`electron-main sendStatusToWindow ${text}`)
  mainWindow.webContents.send("autoUpdater", text)
}

// autoUpdater.on("checking-for-update", () => {
//   logger.info("electron-main checking-for-update")
//   sendStatusToWindow("Checking for update...")
// })
// autoUpdater.on("update-available", (info) => {
//   logger.info(`electron-main update-available ${JSON.stringify(info)}`)
//   sendStatusToWindow("Update available.")
// })
// autoUpdater.on("update-not-available", (info) => {
//   logger.info(`electron-main update-not-available ${JSON.stringify(info)}`)
//   sendStatusToWindow("Update not available.")
// })
// autoUpdater.on("error", (err) => {
//   logger.info(`electron-main error ${JSON.stringify(err)}`)
//   sendStatusToWindow("Error in auto-updater. " + err)
// })
// autoUpdater.on("download-progress", (progressObj) => {
//   logger.info(`electron-main download-progress ${JSON.stringify(progressObj)}`)
//   let log_message = "Download speed: " + progressObj.bytesPerSecond
//   log_message = log_message + " - Downloaded " + progressObj.percent + "%"
//   log_message = log_message + " (" + progressObj.transferred + "/" + progressObj.total + ")"
//   sendStatusToWindow(log_message)
// })
// autoUpdater.on("update-downloaded", (info) => {
//   logger.info(`electron-main update-downloaded ${JSON.stringify(info)}`)
//   sendStatusToWindow("Update downloaded")
// })
