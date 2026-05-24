import child_process from "child_process"
import { stat } from "node:fs/promises"
const { default: PQueue } = require("p-queue")
const axios = require("axios")
const path = require("upath")
const logger = require("./logger")
const rxjs = require("rxjs")

export class Daemon {
  constructor (backend) {
    this.isDoneRecalculatingServiceNodes = false
    this.backend = backend
    this.daemonRPCProcesses = []
    this.heartbeat = null
    this.heartbeat_slow = null
    this.id = 0
    this.net_type = "mainnet"
    this.local = false // do we have a local daemon ?

    this.queue = new PQueue({ concurrency: 1 })
    this.isQuitting = false
    this.height_Subscription = null
    this.height = 0
    this.maxRetries = 3
    this.timeoutMs = 30000 // 30 seconds
  }

  async checkVersion () {
    logger.info("daemon checkVersion")
    try {
      if (process.platform === "win32") {
        const arqmad_path = path.join(global.__binDirectory, "arqmad.exe")
        const arqmad_version_cmd = `"${arqmad_path}" --version`
        if (!await stat(arqmad_path)) {
          return false
        }
        return await new Promise((resolve, reject) => {
          child_process.exec(arqmad_version_cmd, (error, stdout, stderr) => {
            if (error) {
              resolve(false)
            }
            resolve(stdout)
          })
        })
      } else {
        const arqmad_path = path.join(global.__binDirectory, "arqmad")
        const arqmad_version_cmd = `"${arqmad_path}" --version`
        const stats = await stat(arqmad_path)
        if (!stats.isFile()) {
          return false
        }
        return await new Promise((resolve, reject) => {
          child_process.exec(arqmad_version_cmd, (error, stdout, stderr) => {
            if (error) {
              resolve(false)
            }
            resolve(stdout)
          })
        })
      }
    } catch (error) {
      logger.error(`daemon checkVersion ${error.stack || error}`)
      return false
    }
  }

  async checkRemote (daemon) {
    logger.info("daemon checkRemote")
    if (daemon.type === "local") {
      return {}
    }

    try {
      const parameters = {
        protocol: "http://",
        hostname: daemon.remote_host,
        port: daemon.remote_port
      }
      logger.info(`daemon checkRemote ${JSON.stringify(parameters, null, 2)}`)
      const data = await this.sendRPC("get_info", {}, parameters)
      if (data.error) {
        logger.error(`daemon checkRemote ${data.error}`)
        return { error: data.error }
      }
      const result = {
        net_type: data.result.nettype
      }
      logger.info(`daemon checkRemote ${JSON.stringify(result, null, 2)}`)
      return result
    } catch (error) {
      logger.error(`daemon checkRemote ${error.stack || error}`)
      return { error }
    }
  }

  async start (options) {
    logger.info("daemon start")
    const { net_type } = options.app
    const daemon = options.daemons[net_type]
    if (daemon.type === "remote") {
      this.local = false

      // save this info for later RPC calls
      this.protocol = "http://"
      this.hostname = daemon.remote_host
      this.port = daemon.remote_port
      try {
        const data = await this.sendRPC("get_info")
        if (!data.hasOwnProperty("error")) {
          this.startHeartbeat()
        }
      } catch (error) {}
    } else {
      try {
        this.local = true
        const args = [
          "--data-dir", options.app.data_dir,
          "--p2p-bind-ip", daemon.p2p_bind_ip,
          "--p2p-bind-port", daemon.p2p_bind_port,
          "--rpc-bind-ip", daemon.rpc_bind_ip,
          "--rpc-bind-port", daemon.rpc_bind_port,
          "--out-peers", daemon.out_peers,
          "--in-peers", daemon.in_peers,
          "--limit-rate-up", daemon.limit_rate_up,
          "--limit-rate-down", daemon.limit_rate_down,
          "--log-level", daemon.log_level
        ]

        console.log(`Starting daemon with args: ${args}`)

        const dirs = {
          mainnet: options.app.data_dir,
          stagenet: path.join(options.app.data_dir, "stagenet"),
          testnet: path.join(options.app.data_dir, "testnet")
        }

        this.net_type = net_type

        if (net_type === "testnet") {
          args.push("--testnet")
        } else if (net_type === "stagenet") {
          args.push("--stagenet")
        }

        args.push("--log-file", path.join(dirs[net_type], "logs", "daemon.log"))

        if (daemon.rpc_bind_ip !== "127.0.0.1") { args.push("--confirm-external-bind") }

        // TODO: Check if we need to push this command for staging too
        if (daemon.type === "local_remote" && net_type === "mainnet") {
          args.push(
            "--bootstrap-daemon-address",
            `${daemon.remote_host}:${daemon.remote_port}`
          )
        }

        // save this info for later RPC calls
        this.protocol = "http://"
        this.hostname = daemon.rpc_bind_ip
        this.port = daemon.rpc_bind_port

        logger.info(`daemon ${args}`)

        if (process.platform === "win32") {
          this.daemonRPCProcesses.push(child_process.spawn(path.join(global.__binDirectory, "arqmad.exe"), args))
        } else {
          this.daemonRPCProcesses.push(child_process.spawn(path.join(global.__binDirectory, "arqmad"), args, {
            detached: true
          }))
        }
        let daemonRPCProcess = this.daemonRPCProcesses[0]
        daemonRPCProcess.stdout.on("data", data => {
          process.stdout.write(`Daemon: ${data}`)
          const lines = data.toString()
          if (!this.isDoneRecalculatingServiceNodes && lines.includes("Recalculating service nodes list")) {
            this.isDoneRecalculatingServiceNodes = true
            this.sendGateway("set_app_data", {
              status: {
                code: 8 // Recalculating service nodes list
              }
            })
          }
        })
        daemonRPCProcess.on("error", err => {
          process.stderr.write(`Daemon: ${err}`)
        })
        daemonRPCProcess.on("close", code => {
          process.stderr.write(`Daemon: exited with code ${code} \n`)
          daemonRPCProcess = null
        })

        // To let caller know when the daemon is ready
        while (true) {
          if (this.isQuitting) {
            break
          }
          try {
            const data = await this.sendRPC("get_info")
            if (!data.hasOwnProperty("error")) {
              this.startHeartbeat()
              break
            } else {
              if (daemonRPCProcess &&
                                data.error &&
                                data.error.cause === "ECONNREFUSED") {
                // Ignore unless quit has been called
                if (this.isQuitting) {
                  break
                }
              } else {
                throw new Error("Could not connect to local daemon")
              }
            }
          } catch (error) {
            throw new Error("Could not connect to local daemon")
          }
          await this.pause(1000)
        }
      } catch (error) {
        logger.error(`daemon start ${error.stack || error}`)
      }
    }
  }

  async register_sn () {
    try {
      logger.info("daemon register_sn")
      const command = "register_sn"
      this.daemonRPCProcesses[0].stdin.write(`${command}\n`)
    } catch (error) {
      logger.error(`daemon register_sn ${error.stack || error}`)
    }
  }

  async handle (data) {
    try {
      const params = data.data

      switch (data.method) {
        case "ban_peer":
          this.banPeer(params.host, params.seconds)
          break
        case "check_version": {
          const version = await this.checkVersion()
          this.sendGateway("daemon_version", { version })
        }
          break
        default:
      }
    } catch (error) {
      logger.error(`daemon handle ${error.stack || error}`)
    }
  }

  async banPeer (host, seconds = 3600) {
    logger.info("daemon banPeer")
    if (!seconds) { seconds = 3600 }

    const params = {
      bans: [{
        host,
        seconds,
        ban: true
      }]
    }
    try {
      const data = await this.sendRPC("set_bans", params)
      if (data.hasOwnProperty("error") || !data.hasOwnProperty("result")) {
        this.sendGateway("show_notification", { type: "negative", message: "Error banning peer", timeout: 3000 })
        return
      }

      const end_time = new Date(Date.now() + seconds * 1000).toLocaleString()
      this.sendGateway("show_notification", { message: "Banned " + host + " until " + end_time, timeout: 3000 })

      // Send updated peer and ban list
      this.heartbeatSlowAction()
    } catch (error) {
      logger.error(`daemon banPeer ${error.stack || error}`)
      this.sendGateway("show_notification", { type: "negative", message: "Error banning peer", timeout: 3000 })
    }
  }

  timestampToHeight (timestamp, pivot = null, recursion_limit = null) {
    try {
      logger.info("daemon timestampToHeight")
      return new Promise((resolve, reject) => {
        if (timestamp > 999999999999) {
          // We have got a JS ms timestamp, convert
          timestamp = Math.floor(timestamp / 1000)
        }

        pivot = pivot || [137500, 1528073506]
        recursion_limit = recursion_limit || 0

        const diff = Math.floor((timestamp - pivot[1]) / 240)
        const estimated_height = pivot[0] + diff

        if (estimated_height <= 0) {
          return resolve(0)
        }

        if (recursion_limit > 10) {
          return resolve(pivot[0])
        }
        this.getRPC("block_header_by_height", { height: estimated_height }).then((data) => {
          if (data.hasOwnProperty("error") || !data.hasOwnProperty("result")) {
            if (data.error.code === -2) { // Too big height
              this.getRPC("last_block_header").then((data) => {
                if (data.hasOwnProperty("error") || !data.hasOwnProperty("result")) {
                  return
                }

                const new_pivot = [data.result.block_header.height, data.result.block_header.timestamp]

                // If we are within an hour that is good enough
                // If for some reason there is a > 1h gap between blocks
                // the recursion limit will take care of infinite loop
                if (Math.abs(timestamp - new_pivot[1]) < 3600) {
                  return resolve(new_pivot[0])
                }

                // Continue recursion with new pivot
                resolve(new_pivot)
              })
              return
            } else {
              return
            }
          }

          const new_pivot = [data.result.block_header.height, data.result.block_header.timestamp]

          // If we are within an hour that is good enough
          // If for some reason there is a > 1h gap between blocks
          // the recursion limit will take care of infinite loop
          if (Math.abs(timestamp - new_pivot[1]) < 3600) {
            return resolve(new_pivot[0])
          }

          // Continue recursion with new pivot
          resolve(new_pivot)
        })
      }).then((pivot_or_height) => {
        return Array.isArray(pivot_or_height)
          ? this.timestampToHeight(timestamp, pivot_or_height, recursion_limit + 1)
          : pivot_or_height
        // eslint-disable-next-line
        }).catch(error => {
        logger.error(`daemon timestampToHeight ${error.stack || error}`)
        return false
      })
    } catch (error) {
      logger.error(`daemon timestampToHeight ${error.stack || error}`)
    }
  }

  startHeartbeat () {
    try {
      logger.info("daemon startHeartbeat")
      clearInterval(this.heartbeat)
      this.heartbeat = setInterval(() => {
        this.heartbeatAction()
      }, this.local ? 5 * 1000 : 60 * 1000) // 5 seconds for local daemon, 30 seconds for remote
      this.heartbeatAction()

      clearInterval(this.heartbeat_slow)
      this.heartbeat_slow = setInterval(() => {
        this.heartbeatSlowAction()
      }, 60 * 1000) // 60 seconds
      this.heartbeatSlowAction()
    } catch (error) {
      logger.error(`daemon startHeartbeat ${error.stack || error}`)
    }
  }

  stopHeartbeats () {
    try {
      logger.info("daemon stopHeartbeats")
      if (this.heartbeat) {
        clearInterval(this.heartbeat)
        this.heartbeat = null
      }
      if (this.heartbeat_slow) {
        clearInterval(this.heartbeat_slow)
        this.heartbeat_slow = null
      }
    } catch (error) {
      logger.error(`daemon stopHeartbeats ${error.stack || error}`)
    }
  }

  async heartbeatAction () {
    try {
      logger.info("daemon heartbeatAction")
      const data = await this.getRPC("info")
      const daemon_info = {}
      if (data && data.result) {
        daemon_info.info = data.result
        if (this.height < daemon_info.info.height) {
          this.sendGateway("set_daemon_data", daemon_info)
          this.height = daemon_info.info.height
          if (!this.height_Subscription) {
            this.height_Subscription = new rxjs.BehaviorSubject(this.height)
          } else {
            this.height_Subscription.next(this.height)
          }
        }
      }
    } catch (error) {
      logger.error(`daemon heartbeatAction ${error.stack || error}`)
    }
  }

  async heartbeatSlowAction () {
    try {
      logger.info("daemon heartbeatSlowAction")
      let actions = []
      if (this.local) {
        actions = [
          this.getRPC("connections"),
          this.getRPC("bans")
        ]

        const data = await Promise.all(actions)
        const daemon_info = {}
        for (const n of data) {
          if (n === undefined || !n.hasOwnProperty("result") || n.result === undefined) { continue }
          if (n.method === "get_connections" && n.result.hasOwnProperty("connections")) {
            daemon_info.connections = n.result.connections
          } else if (n.method === "get_bans" && n.result.hasOwnProperty("bans")) {
            daemon_info.bans = n.result.bans
          } else if (n.method === "get_txpool_backlog" && n.result.hasOwnProperty("backlog")) {
            daemon_info.tx_pool_backlog = n.result.backlog
          }
        }
        this.sendGateway("set_daemon_data", daemon_info)
      }
    } catch (error) {
      logger.error(`daemon heartbeatSlowAction ${error.stack || error}`)
    }
  }

  sendGateway (method, data) {
    try {
      logger.info("daemon sendGateway")
      if (!this.isQuitting && this.backend) { this.backend.send(method, data) }
    } catch (error) {
      logger.error(`daemon sendGateway ${error.stack || error}`)
    }
  }

  parseDaemonResponse (res) {
    if (res.status === 200) {
      if ("result" in res.data) {
        return res.data
      } else {
        const error = new Error("RPC Error!")
        error.code = res.data.error.code
        error.message = res.data.error.message
        throw error
      }
    } else {
      logger.error(`daemon, parseDaemonResponse, ${JSON.stringify(res.error)}`)
      const error = new Error("HTTP Error!")
      error.code = res.status
      error.message = res.error // res.data
      throw error
    }
  }

  async sendRPC (method, params = {}, options = {}) {
    if (this.isQuitting) {
      return
    }
    const id = this.id++

    const protocol = options.protocol || this.protocol
    const hostname = options.hostname || this.hostname
    const port = options.port || this.port

    const url = `${protocol}${hostname}:${port}/json_rpc`

    const requestOptions = {
      jsonrpc: "2.0",
      id,
      method
    }
    if (Object.keys(params).length !== 0) {
      requestOptions.params = params
    }
    requestOptions.headers = {
      "Content-Length": requestOptions.data ? requestOptions.data.length : 0,
      "Content-Type": "application/json",
      Accept: "application/json"
    }

    return this.queue.add(async () => {
      for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
        if (this.isQuitting) {
          return
        }
        try {
          const response = await Promise.race([
            axios.post(url, requestOptions),
            new Promise((resolve, reject) =>
              setTimeout(() => reject(new Error("RPC request timed out")), this.timeoutMs)
            )
          ])
          const data = this.parseDaemonResponse(response)
          return {
            method,
            params,
            result: data && data.result ? data.result : ""
          }
        } catch (error) {
          logger.error(`daemon, sendRPC, ${JSON.stringify(requestOptions, null, 2)} attempt: ${attempt} ${JSON.stringify(error)}`)
          if (attempt === this.maxRetries) {
            return {
              method,
              params,
              error: {
                code: error.code ? error.code : "",
                message: error.message,
                cause: error.code ? error.code : ""
              }
            }
          }
          // Optionally, add a small delay before retrying
          await new Promise(resolve => setTimeout(resolve, 500))
        }
      }
    })
  }

  /**
     * Call one of the get_* RPC calls
     */
  getRPC (parameter, args) {
    return this.sendRPC(`get_${parameter}`, args)
  }

  pause (miliseconds = 5000) {
    return new Promise((resolve, reject) => setTimeout(resolve, miliseconds))
  }

  async quit () {
    logger.info("daemon quit")
    this.isQuitting = true
    await this.pause(2000)
    this.backend = null
    this.stopHeartbeats()
    for (let index = this.daemonRPCProcesses.length - 1; index >= 0; index--) {
      const daemonRPCProcess = this.daemonRPCProcesses[index]
      daemonRPCProcess.kill("SIGTERM")
    }
  }
}
