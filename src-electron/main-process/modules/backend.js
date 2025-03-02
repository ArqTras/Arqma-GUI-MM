import { Daemon } from "./daemon"
import { WalletRPC } from "./wallet-rpc"
import { dialog } from "electron"
import { writeFile, mkdir, readFile } from "node:fs/promises"
import { existsSync } from "node:fs"
const electron = require("electron")
const axios = require("axios")
const os = require("os")
const path = require("path")
const objectAssignDeep = require("object-assign-deep")
const logger = require("./logger")

export class Backend {
  constructor (mainWindow) {
    logger.info("backend constructor")
    this.mainWindow = mainWindow
    this.daemon = null
    this.walletd = null
    this.token = null
    this.config_dir = null
    this.wallet_dir = null
    this.config_file = null
    this.config_data = {}
    this.defaultRemotes = [
      {
        host: "node1.arqma.com",
        port: 19994
      },
      {
        host: "node2.arqma.com",
        port: 19994
      },
      {
        host: "node3.arqma.com",
        port: 19994
      },
      {
        host: "node4.arqma.com",
        port: 19994
      },
      {
        host: "arq.gntl.uk",
        port: 19994
      }
    ]
    this.ethereum = {
      ethereum_network_index: "0",
      networks: [
        [
          {
            token_name: "ETH",
            network: "ethereum",
            id: 1,
            token_address: "0x0d40aD54EDc0A3632A1996e5f8fd10b91f298A27",
            bridge_address: "0x631a2C078aE1dF2d04062DEca539197Ef5AC546e",
            explorer: "https://etherscan.io/tx/",
            governance: "Tw1WW1jYkS3144DkXTDQgg6j2fDk28KuDeYdQZb91UvnZ462yRExJz2h7k116wXbRp4JhcYyfb3PabpTuaRX9DiG2U5kGJ6wS"
          },
          {
            token_name: "BNB",
            network: "bnb",
            id: 56,
            token_address: "0x0d40aD54EDc0A3632A1996e5f8fd10b91f298A27",
            bridge_address: "0x631a2C078aE1dF2d04062DEca539197Ef5AC546e",
            explorer: "https://bscscan.com/tx/",
            governance: "Tw1WW1jYkS3144DkXTDQgg6j2fDk28KuDeYdQZb91UvnZ462yRExJz2h7k116wXbRp4JhcYyfb3PabpTuaRX9DiG2U5kGJ6wS"
          }
        ]
      ]
    }
  }

  async init (config) {
    logger.info("backend init")

    if (os.platform() === "win32") {
      this.config_dir = "C:\\ProgramData\\arqma"
      this.wallet_dir = `${os.homedir()}\\Documents\\arqma`
    } else {
      this.config_dir = path.join(os.homedir(), ".arqma")
      this.wallet_dir = path.join(os.homedir(), "arqma")
    }

    if (!existsSync(this.config_dir)) {
      await mkdir(this.config_dir)
    }

    if (!existsSync(path.join(this.config_dir, "gui"))) {
      await mkdir(path.join(this.config_dir, "gui"))
    }

    this.config_file = path.join(this.config_dir, "gui", "config.json")

    const daemon = {
      type: "remote",
      p2p_bind_ip: "0.0.0.0",
      p2p_bind_port: 19993,
      rpc_bind_ip: "127.0.0.1",
      rpc_bind_port: 19994,
      zmq_rpc_bind_ip: "127.0.0.1",
      zmq_rpc_bind_port: 19995,
      out_peers: -1,
      in_peers: -1,
      limit_rate_up: -1,
      limit_rate_down: -1,
      log_level: 0
    }

    const daemons = {
      mainnet: {
        ...daemon,
        remote_host: "node1.arqma.com",
        remote_port: 19994
      },
      stagenet: {
        ...daemon,
        type: "local",
        p2p_bind_port: 29993,
        rpc_bind_port: 29994,
        zmq_rpc_bind_port: 29995
      },
      testnet: {
        ...daemon,
        type: "local",
        p2p_bind_port: 39993,
        rpc_bind_port: 39994,
        zmq_rpc_bind_port: 39995
      }
    }

    // Default values
    let port
    try {
      port = JSON.parse(await readFile(path.join(this.config_dir, "gui", "port.json", "utf8"))).port
    } catch {
      port = 10231
    }
    this.defaults = {
      daemons: objectAssignDeep({}, daemons),
      app: {
        data_dir: this.config_dir,
        wallet_data_dir: this.wallet_dir,
        net_type: "mainnet"
      },
      wallet: {
        rpc_bind_port: 9999,
        log_level: 0
      }
    }

    this.config_data = {
      // Copy all the properties of defaults
      ...objectAssignDeep({}, this.defaults),
      appearance: {
        theme: "dark"
      },
      ...objectAssignDeep({}, { ethereum: this.ethereum })
    }
    // this is too long
    if (this.config_data.app.scan === undefined) {
      this.config_data.app.scan = false
    }

    if (this.config_data.app.promptForPassword === undefined) {
      this.config_data.app.promptForPassword = true
    }

    if (this.config_data.app.daysOfTransactions === undefined) {
      this.config_data.app.daysOfTransactions = 1
    }

    this.config_data.app.loggingLevel = process.env.LOG_LEVEL

    let remotes
    let useDefaultRemotes = true
    let remotesArray = []

    try {
      const remotesFilePath = path.join(this.config_dir, "gui", "remotes.json")
      if (existsSync(remotesFilePath)) {
        remotes = await readFile(remotesFilePath, "utf8")
        remotesArray = JSON.parse(remotes)
        if (remotesArray.length === 0) {
          useDefaultRemotes = true
        } else {
          useDefaultRemotes = false
        }
      }
      remotesArray = remotesArray.map(obj => {
        if (obj && obj.host === "arq.pool.gntl.co.uk") {
          return { ...obj, host: "arq.gntl.uk" }
        }
        return obj
      })
    } catch (error) {
      logger.error(`daemon init ${error.stack || error}`)
    }
    if (useDefaultRemotes) {
      remotes = JSON.stringify(this.defaultRemotes, null, 4)
    } else {
      this.defaultRemotes.forEach(obj2 => {
        if (!remotesArray.some(obj1 =>
          Object.values(obj1).every(value =>
            Object.values(obj2).includes(value)
          )
        )) {
          remotesArray.push(obj2)
        }
      })
      remotes = JSON.stringify(remotesArray, null, 4)
    }

    try {
      await writeFile(path.join(this.config_dir, "gui", "remotes.json"), remotes, "utf8")
    } catch (error) {
      logger.error(`daemon init ${error.stack || error}`)
    }

    this.remotes = JSON.parse(remotes)
  }

  send (event, data = {}) {
    try {
      const message = {
        event,
        data
      }
      this.mainWindow.webContents.send("receive", message)
    } catch (error) {
      logger.error(`backend send ${event}\n${JSON.stringify(message)}`)
    }
  }

  async receive (data) {
    logger.info(`backend receive ${JSON.stringify(data)}`)
    // route incoming request to either the daemon, wallet, or here
    switch (data.module) {
      case "core":
        await this.handle(data)
        break
      case "daemon":
        if (this.daemon) {
          await this.daemon.handle(data)
        }
        break
      case "wallet":
        if (this.walletd) {
          await this.walletd.handle(data)
        }
        break
    }
  }

  async handle (data) {
    logger.info(`backend ${JSON.stringify(data)}`)
    const params = data.data

    switch (data.method) {
      case "set_daysOfTransactions":
        try {
          this.config_data.app.daysOfTransactions = params.daysOfTransactions
        } catch (error) {
          logger.error(`daemon set_daysOfTransactions ${error.stack || error}`)
        }
        break
      case "quick_save_config":
        try {
          // save only partial config settings
          this.config_data.ethereum = Object.assign(this.config_data.ethereum, params)
          await writeFile(this.config_file, JSON.stringify(this.config_data, null, 4), "utf8")
          this.send("set_app_data", {
            config: params,
            pending_config: params
          })
        } catch (error) {
          logger.error(`daemon quick_save_config ${error.stack || error}`)
        }
        break

      case "change_remotes":
        try {
          logger.info(`backend change_remotes ${JSON.stringify(params)}`)
          this.remotes = params
          await writeFile(path.join(this.config_dir, "gui", "remotes.json"), JSON.stringify(params), "utf8")
          this.send("set_app_data", {
            remotes: params
          })
        } catch (error) {
          logger.error(`backend change_remotes ${error.stack || error}`)
        }
        break

      case "change_ethereum":
        try {
          logger.info(`backend change_ethereum", ${JSON.stringify(params)}`)
          this.config_data.ethereum = Object.assign(this.config_data.ethereum, params)
        } catch (error) {
          logger.error(`backend change_remotes ${error.stack || error}`)
        }
        break

      case "change_scan":
        try {
          this.config_data.app.scan = params
          this.send("set_app_data", {
            scan: params
          })
        } catch (error) {
          logger.error(`daemon change_scan ${error.stack || error}`)
        }
        break

      case "save_config": {
        try {
          // check if config has changed
          logger.info("backend save_config", params)
          let config_changed = false
          if (params.daemons.mainnet.remote_host) {
            const remote = this.remotes.find(remote => {
              return remote.host === params.daemons.mainnet.remote_host && remote.port === params.daemons.mainnet.remote_port
            })
            if (!remote) {
              try {
                this.remotes.push({
                  host: params.daemons.mainnet.remote_host,
                  port: params.daemons.mainnet.remote_port
                })
                await writeFile("remotes.json", JSON.stringify(this.remotes, null, 4), "utf8")
              } catch {
              }
            }
          }
          Object.keys(this.config_data).map(i => {
            if (i === "appearance") return
            Object.keys(this.config_data[i]).map(j => {
              if (this.config_data[i][j] !== params[i][j]) {
                config_changed = true
              }
            })
          })
          await this.save_config_init(params, "save_config", config_changed)
        } catch (error) {
          logger.error(`daemon save_config ${error.stack || error}`)
        }
        break
      }
      case "save_config_init":
        try {
          logger.info("backend save_config_init", JSON.stringify(params, null, "\n"))
          await this.save_config_init(params, "save_config_init", false)
        } catch (error) {
          logger.error(`daemon save_config_init ${error.stack || error}`)
        }
        break

      case "init":
        try {
          await this.startup()
        } catch (error) {
          logger.error(`daemon init ${error.stack || error}`)
        }
        break

      case "open_explorer": {
        try {
          let endPoint = ""
          if (params.type === "tx") {
            endPoint = "tx"
          } else if (params.type === "service_node") {
            endPoint = "service_node"
          } else if (params.type === "swap_tx_id") {
            await electron.shell.openExternal(`${params.explorer}${params.id}`)
            return
          }

          if (endPoint) {
            const baseUrl = "https://explorer.arqma.com"
            const url = `${baseUrl}/${endPoint}/`
            await electron.shell.openExternal(url + params.id)
          }
          break
        } catch (error) {
          logger.error(`daemon open_explorer ${error.stack || error}`)
        }
      }
      case "open_url":
        try {
          await electron.shell.openExternal(params.url)
        } catch (error) {
          logger.error(`daemon open_url ${error.stack || error}`)
        }
        break

      case "save_svg": {
        try {
          const result = await dialog.showSaveDialog(this.mainWindow, {
            title: "Save " + params.type,
            filters: [{ name: "SVG", extensions: ["svg"] }],
            defaultPath: os.homedir()
          })

          if (result.filePath) {
            await writeFile(result.filePath, params.svg, "utf8")
            this.send("show_notification", {
              message: params.type + " saved to " + result.filePath,
              timeout: 3000
            })
          }
          break
        } catch (error) {
          logger.error(`daemon save_svg ${error.stack || error}`)
          this.send("show_notification", {
            type: "negative",
            message: "Error saving " + params.type,
            timeout: 3000
          })
        }
      }
      default:
    }
  }

  async save_config_init (params, method, config_changed) {
    logger.info("backend save_config_init")
    try {
      Object.keys(params).map(key => {
        this.config_data[key] = Object.assign(this.config_data[key], params[key])
      })
      const validated = Object.keys(this.defaults)
        .filter(k => k in this.config_data)
        .map(k => [k, this.validate_values(this.config_data[k], this.defaults[k])])
        .reduce((map, obj) => {
          map[obj[0]] = obj[1]
          return map
        }, {})

      // Validate deamon data
      this.config_data = {
        ...this.config_data,
        ...validated
      }
      await writeFile(this.config_file, JSON.stringify(this.config_data, null, 4), "utf8")
      if (method === "save_config_init") {
        await this.startup()
      } else {
        this.send("set_app_data", {
          config: this.config_data,
          pending_config: this.config_data
        })
        if (config_changed) {
          this.send("settings_changed_reboot")
        }
      }
    } catch (error) {
      logger.error(`daemon save_config_init ${error.stack || error}`)
    }
  }

  async startup () {
    logger.info("backend startup")
    this.send("set_app_data", {
      remotes: this.remotes,
      defaults: this.defaults
    })
    logger.info(`backend startup ${this.config_file}`)
    let disk_config_data = {}
    try {
      const data = await readFile(this.config_file, "utf8")
      disk_config_data = JSON.parse(data)
      try {
        if (JSON.stringify(disk_config_data.ethereum.networks[0]) !== JSON.stringify(this.ethereum.networks[0])) {
          disk_config_data.ethereum.networks[0] = this.ethereum.networks[0]
        }
      } catch (error) {
        disk_config_data = objectAssignDeep(disk_config_data, { ethereum: this.ethereum })
        logger.info(`backend startup suspicious ethereum setup ${error}`)
      }
      this.ethereum = { ...disk_config_data.ethereum }
      this.send("set_ethereum_data", this.ethereum)
    } catch (error) {
      logger.info(`backend startup1 ${error}`)
      this.send("set_app_data", {
        status: {
          code: -1 // Config not found
        },
        config: this.config_data,
        pending_config: this.config_data
      })
      return
    }

    // semi-shallow object merge
    Object.keys(disk_config_data).map(key => {
      if (!this.config_data.key) {
        this.config_data[key] = {}
      }
      this.config_data[key] = Object.assign(this.config_data[key], disk_config_data[key])
    })

    let port = ""
    let host = ""
    let fastest_time = 1000000
    if (this.config_data.app.scan) {
      for (const i in this.remotes) {
        if (this.config_data.daemons.mainnet.type === "local") { break }
        const options = {
          method: "POST",
          json: {
            jsonrpc: "2.0",
            id: "0",
            method: "get_info"
          },
          timeout: 2500
        }
        const start = new Date().getTime()

        try {
          await axios("http://" + this.remotes[i].host + ":" + this.remotes[i].port + "/json_rpc", options)
          const end = new Date().getTime() - start
          if (end < fastest_time) {
            port = this.remotes[i].port
            host = this.remotes[i].host
            fastest_time = end
          }
          logger.info(`backend http://${this.remotes[i].host}:${this.remotes[i].port}/json_rpc, ${fastest_time}`)
        } catch {
          logger.error(`backend http://${this.remotes[i].host}:${this.remotes[i].port}/json_rpc, is down`)
        }
      }
    }

    if (port) {
      this.config_data.daemons.mainnet.remote_host = host
      this.config_data.daemons.mainnet.remote_port = port
    }

    // here we may want to check if config data is valid, if not also send code -1
    // i.e. check ports are integers and > 1024, check that data dir path exists, etc
    const validated = Object.keys(this.defaults)
      .filter(k => k in this.config_data)
      .map(k => [k, this.validate_values(this.config_data[k], this.defaults[k])])
      .reduce((map, obj) => {
        map[obj[0]] = obj[1]
        return map
      }, {})

    // Make sure the daemon data is valid
    this.config_data = {
      ...this.config_data,
      ...validated
    }

    // save config file back to file, so updated options are stored on disk
    await writeFile(this.config_file, JSON.stringify(this.config_data, null, 4), "utf8")

    this.send("set_app_data", {
      config: this.config_data,
      pending_config: this.config_data,
      selected_node: `${host}:${port}`
    })

    this.send("set_ethereum_data", this.ethereum)

    // Make the wallet dir
    const { wallet_data_dir, data_dir } = this.config_data.app
    if (!existsSync(wallet_data_dir)) {
      await mkdir(wallet_data_dir)
    }

    // Check to see if data and wallet directories exist
    const dirs_to_check = [{
      path: data_dir,
      error: "Data Storage path not found"
    },
    {
      path: wallet_data_dir,
      error: "Wallet Data Storage path not found"
    }]

    for (const dir of dirs_to_check) {
      // Check to see if dir exists
      if (!existsSync(dir.path)) {
        this.send("show_notification", {
          type: "negative",
          message: `Error: ${dir.error}`,
          timeout: 3000
        })

        // Go back to config
        this.send("set_app_data", {
          status: {
            code: -1 // Return to config screen
          }
        })
        return
      }
    }

    const { net_type } = this.config_data.app

    const dirs = {
      mainnet: this.config_data.app.data_dir,
      stagenet: path.join(this.config_data.app.data_dir, "stagenet"),
      testnet: path.join(this.config_data.app.data_dir, "testnet")
    }

    // Make sure we have the directories we need
    const net_dir = dirs[net_type]
    if (!existsSync(net_dir)) {
      await mkdir(net_dir)
    }

    const log_dir = path.join(net_dir, "logs")
    if (!existsSync(log_dir)) {
      await mkdir(log_dir)
    }

    this.daemon = new Daemon(this)
    this.walletd = new WalletRPC(this)

    this.send("set_app_data", {
      status: {
        code: 3 // Starting daemon
      }
    })

    // Make sure the remote node provided is accessible
    const config_daemon = this.config_data.daemons[net_type]

    const remoteNodeData = await this.daemon.checkRemote(config_daemon)
    if (remoteNodeData.error) {
      logger.error(`backend startup : Could not acess remote node: ${JSON.stringify(remoteNodeData.error)}`)
      // If we can default to local then we do so, otherwise we tell the user  to re-set the node
      if (config_daemon.type === "local_remote") {
        this.config_data.daemons[net_type].type = "local"
        this.send("set_app_data", {
          config: this.config_data,
          pending_config: this.config_data
        })
        this.send("show_notification", {
          type: "warning",
          textColor: "black",
          message: "Warning: Could not access remote node, switching to local only",
          timeout: 3000
        })
      } else {
        this.send("show_notification", {
          type: "negative",
          message: "Error: Could not access remote node, please try another remote node",
          timeout: 3000
        })

        // Go back to config
        this.send("set_app_data", {
          status: {
            code: -1 // Return to config screen
          }
        })
        return
      }
    }

    // If we got a net type back then check if ours match
    if (remoteNodeData.net_type && remoteNodeData.net_type !== net_type) {
      this.send("show_notification", {
        type: "negative",
        message: "Error: Remote node is using a different nettype",
        timeout: 3000
      })

      // Go back to config
      this.send("set_app_data", {
        status: {
          code: -1 // Return to config screen
        }
      })
      return
    }

    const version = await this.daemon.checkVersion()
    if (version) {
      this.send("set_app_data", {
        status: {
          code: 4,
          message: version
        }
      })
    } else {
      // daemon not found, probably removed by AV, set to remote node
      this.config_data.daemons[net_type].type = "remote"
      this.send("set_app_data", {
        status: {
          code: 5
        },
        config: this.config_data,
        pending_config: this.config_data
      })
    }

    try {
      await this.daemon.start(this.config_data)
      this.send("set_app_data", {
        status: {
          code: 6 // Starting wallet
        }
      })
    } catch (error) {
      logger.error(`backend startup2 ${error}`)
      if (this.config_data.daemons[net_type].type === "remote") {
        this.send("show_notification", { type: "negative", message: "Remote daemon can not be reached", timeout: 3000 })
      } else {
        this.send("show_notification", { type: "negative", message: "Local daemon internal error", timeout: 3000 })
      }
      this.send("set_app_data", {
        status: {
          code: -1 // Return to config screen
        }
      })
      return
    }

    try {
      await this.walletd.start(this.config_data)
      this.send("set_app_data", {
        status: {
          code: 7 // Reading wallet list
        }
      })

      await this.walletd.listWallets(true)

      this.send("set_app_data", {
        status: {
          code: 0 // Ready
        }
      })
    } catch (error) {
      logger.error(`backend startup3 ${error}`)
      this.send("set_app_data", {
        status: {
          code: -1 // Return to config screen
        }
      })
    }
  }

  async quit () {
    try {
      if (this.walletd) {
        await this.walletd.quit()
        this.walletd = null
      }
      if (this.daemon) {
        await this.daemon.quit()
        this.daemon = null
      }
      this.mainWindow = null
    } catch (error) {
      logger.error(`backend quit ${error.stack || error}`)
    } finally {
      logger.info("backend quit close")
    }
  }

  // Replace any invalid value with default values
  validate_values (values, defaults) {
    try {
      const isDictionary = (v) => typeof v === "object" && v !== null && !(v instanceof Array) && !(v instanceof Date)
      const modified = { ...values }

      // Make sure we have valid defaults
      if (!isDictionary(defaults)) return modified

      for (const key in modified) {
        // Only modify if we have a default
        if (!(key in defaults)) continue

        const defaultValue = defaults[key]
        const invalidDefault = defaultValue === null || defaultValue === undefined || Number.isNaN(defaultValue)
        if (invalidDefault) continue

        const value = modified[key]

        // If we have a object then recurse through it
        if (isDictionary(value)) {
          modified[key] = this.validate_values(value, defaultValue)
        } else {
          // Check if we need to replace the value
          const isValidValue = !(value === undefined || value === null || value === "" || Number.isNaN(value))
          if (isValidValue) continue

          // Otherwise set the default value
          modified[key] = defaultValue
        }
      }
      return modified
    } catch (error) {
      logger.error(`daemon validate_values ${error.stack || error}`)
    }
  }
}
