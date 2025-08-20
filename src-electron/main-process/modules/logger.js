const fs = require("fs")
const path = require("path")
const electron = require("electron")
const winston = require("winston")
const { combine, timestamp, printf, align } = winston.format
const { getAppDataPath } = require("../../app-data-path")
const VERSION = "3.8.1"

const dotenv = require("dotenv")
let environmentFile = ""
if (process.env.NODE_ENV === "development") {
  environmentFile = path.join(process.cwd(), ".env").replace(/\\/g, "\\\\")
} else {
  const environmentDirectory = getAppDataPath("Arqma-Electron-Wallet")
  environmentFile = path.join(environmentDirectory, ".env").replace(/\\/g, "\\\\")
}

if (!fs.existsSync(environmentFile)) {
  fs.writeFileSync(environmentFile, `LOG_LEVEL=info\nCUSTOM_VERSION=${VERSION}`)
}

dotenv.config({ path: environmentFile })

let filename = "Arqma.log"
if (process.env.NODE_ENV !== "development") {
  filename = path.join(electron.app.getPath("userData"), "logs", "Arqma.log")
}

const silent = false
const level = process.env.LOG_LEVEL || "error"
let transports = []

process.env.CUSTOM_VERSION = VERSION

if (level === "error") {
  transports = [new winston.transports.Console({ colorize: { all: true } }), new winston.transports.File({ filename, level: "error", colorize: false })]
}

if (level === "info") {
  transports = [new winston.transports.Console({ colorize: { all: true } }), new winston.transports.File({ filename, level: "info", colorize: false })]
}

const removePrivate = winston.format((info, opts) => {
  let messageAsString = JSON.stringify(info.message)
  if (messageAsString.includes("password")) {
    try {
      info.message = ObfusticatePrivateValues(messageAsString, "password")
    } catch (error) {
      return false
    }
  }
  if (messageAsString.includes("seed")) {
    try {
      messageAsString = JSON.stringify(info.message)
      info.message = ObfusticatePrivateValues(messageAsString, "seed")
    } catch (error) {
      return false
    }
  }
  if (messageAsString.includes("password_confirm")) {
    try {
      messageAsString = JSON.stringify(info.message)
      info.message = ObfusticatePrivateValues(messageAsString, "password_confirm")
    } catch (error) {
      return false
    }
  }
  return info
})

const ObfusticatePrivateValues = (messageAsString, key) => {
  const firstBraceIndex = messageAsString.indexOf("{", 0)
  const prefix = messageAsString.slice(0, firstBraceIndex)
  const preparedJsonString = messageAsString.slice(firstBraceIndex, messageAsString.length - 1).replace(/\\/g, "")
  const preparedJson = JSON.parse(preparedJsonString)
  preparedJson.data[key] = "******"
  return `${prefix} ${JSON.stringify(preparedJson)}`
}

const logger = winston.createLogger({
  level,
  silent,
  format: combine(
    removePrivate(),
    timestamp({
      format: "YYYY-MM-DD hh:mm:ss"
    }),
    align(),
    printf((info) => `${info.timestamp} ${info.level}: ${info.message}`)
  ),
  transports
})

exports = module.exports = logger
