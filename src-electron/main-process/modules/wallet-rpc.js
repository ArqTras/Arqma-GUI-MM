/* eslint-disable no-constant-condition */
import child_process from "child_process"
import {
  writeFile,
  stat,
  mkdir,
  readFile,
  truncate,
  unlink,
  copyFile,
  readdir,
  constants,
  rename,
  rmdir
} from "node:fs/promises"
import { existsSync, mkdirSync } from "node:fs"
const { default: PQueue } = require("p-queue")
const axiosDigest = require("./axiosDigest")
const os = require("os")
const path = require("upath")
const crypto = require("crypto")
const logger = require("./logger")
const axios = require("axios")
const fs = require("fs")
// const zmq = require("zeromq")
const { Observable, Subject, fromEvent } = require("rxjs")
const Decimal = require("decimal.js")

export class WalletRPC {
  constructor (backend) {
    this.subscriber = null
    this.heightEmitter = null
    this.timeout = 5000
    this.stakeAcquisition = null
    this.isQuitting = false
    this.tx_metadata_list = []
    this.walletRPCProcesses = []
    this.backend = backend
    this.data_dir = null
    this.wallet_dir = null
    this.auth = []
    this.id = 0
    this.net_type = "mainnet"
    this.heartbeat = null
    this.height_check = {
      address: 0,
      pools: 0,
      stake: 0,
      txs: 0
    }
    this.confirmed_stake = false
    this.cancel_stake = false
    this.wallet_state = {
      address: "",
      open: false,
      name: "",
      password_hash: null,
      balance: null,
      unlocked_balance: null,
      password: "",
      height: 0
    }
    this.dirs = null
    this.last_height_send_time = Date.now() / 1000
    this.local = true

    this.height_regexes = [
      {
        string: /Processed block: <([a-f0-9]+)>, height (\d+)/,
        height: (match) => match[2]
      },
      {
        string: /Skipped block by height: (\d+)/,
        height: (match) => match[1]
      },
      {
        string: /Skipped block by timestamp, height: (\d+)/,
        height: (match) => match[1]
      },
      {
        string: /Blockchain sync progress: <([a-f0-9]+)>, height (\d+)/,
        height: (match) => match[2]
      }
    ]
    this.queue = new PQueue({ concurrency: 1 })
    this.STAKING_SHARE_PARTS = new Decimal("18446744073709551612")
    this.coinUnits = 10 ** 9
  }

  // this function will take an options object for testnet, data-dir, etc
  async start (options) {
    try {
      logger.info("wallet  start")
      const { net_type, wallet_data_dir, data_dir } = options.app
      const daemon = options.daemons[net_type]
      let daemon_address = `${daemon.rpc_bind_ip}:${daemon.rpc_bind_port}`
      if (daemon.type === "remote") {
        this.local = false
        daemon_address = `${daemon.remote_host}:${daemon.remote_port}`
      }

      const buffer = crypto.randomBytes(64 + 64 + 32)
      const auth = buffer.toString("hex")

      this.auth = [
        auth.slice(0, 64), // rpc username
        auth.slice(64, 64), // rpc password
        auth.slice(128, 32) // password salt
      ]

      const args = [
        "--rpc-login",
        this.auth[0] + ":" + this.auth[1],
        "--rpc-bind-port",
        options.wallet.rpc_bind_port,
        "--daemon-address",
        daemon_address,
        // "--log-level", options.wallet.log_level,
        "--log-level",
        // "--trusted-daemon",
        "*:WARNING,net*:FATAL,net.http:DEBUG,global:INFO,verify:FATAL,stacktrace:INFO"
      ]

      this.net_type = net_type
      this.data_dir = data_dir
      this.wallet_data_dir = wallet_data_dir

      this.dirs = {
        mainnet: this.wallet_data_dir,
        stagenet: path.join(this.wallet_data_dir, "stagenet"),
        testnet: path.join(this.wallet_data_dir, "testnet")
      }

      this.wallet_dir = path.join(this.dirs[net_type], "wallets")
      args.push("--wallet-dir", this.wallet_dir)

      const log_file = path.join(
        this.dirs[net_type],
        "logs",
        "arqma-wallet-rpc.log"
      )
      args.push("--log-file", log_file)

      if (net_type === "testnet") {
        args.push("--testnet")
      } else if (net_type === "stagenet") {
        args.push("--stagenet")
      }

      if (existsSync(log_file)) {
        await truncate(log_file, 0)
      }

      if (!existsSync(this.wallet_dir)) {
        await mkdir(this.wallet_dir, { recursive: true })
      }
      logger.info(`wallet ${args}`)
      if (process.platform === "win32") {
        this.walletRPCProcesses.push(
          child_process.spawn(
            path.join(global.__binDirectory, "arqma-wallet-rpc.exe"),
            args
          )
        )
      } else {
        this.walletRPCProcesses.push(
          child_process.spawn(
            path.join(global.__binDirectory, "arqma-wallet-rpc"),
            args,
            {
              detached: false
            }
          )
        )
      }

      // save this info for later RPC calls
      this.protocol = "http://"
      this.hostname = "127.0.0.1"
      this.port = options.wallet.rpc_bind_port

      this.axiosDigest = axiosDigest.createHttpClient({
        username: this.auth[0],
        password: this.auth[1]
      })
      this.axiosDigest.defaults.httpAgent.options.rejectUnauthorized = false
      this.axiosDigest.defaults.httpsAgent.options.rejectUnauthorized = false

      this.isRPCSyncing = false
      const walletRPCProcess = this.walletRPCProcesses[0]
      walletRPCProcess.stdout.on("data", (data) => {
        process.stdout.write(`Wallet: ${data}`)

        const lines = data.toString().split("\n")
        let match
        let height = null

        for (const line of lines) {
          for (const regex of this.height_regexes) {
            match = line.match(regex.string)
            if (match) {
              height = regex.height(match)
              this.isRPCSyncing = true
              break
            }
          }
        }

        const now = Date.now() / 1000
        if (height && now - this.last_height_send_time >= 5) {
          // NOTE: we divided by 1000 so seconds are not expressed as 1000 anymore. duh!
          this.last_height_send_time = now
          this.sendGateway("set_wallet_info", {
            height
          })
        }
      })
      walletRPCProcess.on("error", (error) => {
        logger.error(
          `wallet start: RPCProcess error ${error.stack || error}`
        )
        process.stderr.write(`Wallet: ${error}`)
      })
      walletRPCProcess.on("close", (code) => {
        logger.info(`wallet start: RPCProcess close ${code}`)
        process.stderr.write(`Wallet: exited with code ${code} \n`)
      })

      // To let caller know when the wallet is ready
      while (true) {
        if (this.isQuitting) {
          break
        }
        try {
          const data = await this.sendRPC("get_languages")
          if (!data.hasOwnProperty("error")) {
            break
          } else {
            if (
              walletRPCProcess &&
                            data.error &&
                            data.error.cause === "ECONNREFUSED"
            ) {
              // Ignore unless quit has been called
              if (this.isQuitting) {
                break
              }
            } else {
              throw new Error("Could not connect to wallet RPC")
            }
          }
        } catch (error) {}
        await this.pause(this.timeout)
      }
    } catch (error) {
      logger.error(`wallet start ${error.stack || error}`)
    }
  }

  async pause (miliseconds = 5000) {
    return new Promise((resolve) => setTimeout(resolve, miliseconds))
  }

  async handle (data) {
    const params = data.data
    switch (data.method) {
      case "has_password":
        this.hasPassword()
        break

      case "validate_address":
        await this.validateAddress(params.address)
        break

      case "copy_old_gui_wallets":
        this.copyOldGuiWallets(params.wallets || [])
        break

      case "list_wallets":
        await this.listWallets()
        break

      case "create_wallet":
        await this.createWallet(
          params.name,
          params.password,
          params.language
        )
        break

      case "restore_wallet":
        await this.restoreWallet(
          params.name,
          params.password,
          params.seed,
          params.refresh_type,
          params.refresh_type === "date"
            ? params.refresh_start_date
            : params.refresh_start_height
        )
        break

      case "restore_view_wallet":
      // TODO: Decide if we want this for arqma
        await this.restoreViewWallet(
          params.name,
          params.password,
          params.address,
          params.viewkey,
          params.refresh_type,
          params.refresh_type === "date"
            ? params.refresh_start_date
            : params.refresh_start_height
        )
        break

      case "import_wallet":
        await this.importWallet(
          params.name,
          params.password,
          params.path
        )
        break

      case "open_wallet":
        await this.openWallet(params.name, params.password)
        break

      case "close_wallet":
        await this.closeWallet()
        break

      case "stake":
        await this.stake(
          params.password,
          params.origin,
          params.amount,
          params.key,
          params.destination
        )
        break

      case "relay_stake":
        await this.relayStake(params.origin)
        break

      case "cancel_stake":
        break

      case "relay_sweepAll":
        await this.relaySweepAll(params.origin)
        break

      case "sweepAll":
        await this.sweepAll(
          params.password,
          params.origin,
          params.do_not_relay
        )
        break

      case "cancelTransaction":
        await this.cancelTransaction(params.type)
        break

      case "register_service_node":
        await this.registerSnode(params.password, params.string)
        break

      case "unlock_stake":
        this.unlockStake(
          params.password,
          params.service_node_key,
          params.confirmed || false
        )
        break

      case "transfer":
        await this.transfer(
          params.password,
          params.amount,
          params.address,
          params.payment_id,
          params.priority,
          params.currency,
          params.note || "",
          params.address_book,
          params.memo || "",
          params.network || 0
        )
        break

      case "relay_transfer":
        await this.relayTransfer()
        break

      case "add_address_book":
        await this.addAddressBook(
          params.address,
          params.payment_id,
          params.description,
          params.name,
          params.starred,
          params.hasOwnProperty("index") ? params.index : false
        )
        break

      case "delete_address_book":
        await this.deleteAddressBook(
          params.hasOwnProperty("index") ? params.index : false
        )
        break

      case "save_tx_notes":
        await this.saveTxNotes(params.txid, params.note)
        break

      case "rescan_blockchain":
        this.rescanBlockchain()
        break
      case "rescan_spent":
        this.rescanSpent()
        break
      case "get_private_keys":
        await this.getPrivateKeys(params.password)
        break
      case "export_key_images":
        await this.exportKeyImages(params.password, params.path, params.all)
        break
      case "import_key_images":
        await this.importKeyImages(params.password, params.path)
        break

      case "change_wallet_password":
        await this.changeWalletPassword(
          params.old_password,
          params.new_password
        )
        break

      case "delete_wallet":
        await this.deleteWallet(params.password)
        break

      case "begin_Stake_Acquisition":
        await this.beginStakeAcquisition()
        break

      case "end_Stake_Acquisition":
        await this.endStakeAcquisition()
        break

      case "get_coin_price":
        await this.getCoinPrice()
        await this.getConversionData()
        break

        //   case "subscribe_for_signature_data":
        //     await this.subscribeForSignatureData(params.ethereumAddress)
        //     break

      case "unsubscribe_for_signature_data":
        await this.endSignatureSubscription()
        break
      case "remove_signature_data":
        await this.removeSignatureData(params.ethereumAddress, params.height, params.signature)
        break

      case "export_transactions":
        await this.exportTransactions(params)
        break
      default:
    }
  }

  endStakeAcquisition () {
    try {
      logger.info("wallet  endStakeAcquisition")
      if (this.heightEmitter) {
        this.heightEmitter.unsubscribe()
        this.heightEmitter = null
      }
    } catch (error) {
      logger.error(`wallet endStakeAcquisition ${error.stack || error}`)
    }
  }

  async endSignatureSubscription () {
    try {
      logger.info("wallet endSignatureSubscription")
      if (this.subscriber !== null) {
        await this.subscriber.send(["", "DE-REGISTER"])
        this.subscriber.close()
        this.subscriber = null
        if (this.subscription) {
          this.subscription.unsubscribe()
          this.subscription = null
        }
      }
      this.sendGateway("set_signature_data", [])
    } catch (error) {
      logger.error(`wallet endSignatureSubscription ${error.stack || error}`)
    }
  }

  async beginStakeAcquisition () {
    try {
      logger.info("wallet  beginStakeAcquisition")
      this.heightEmitter =
                this.backend.daemon.height_Subscription.subscribe(
                  async (height) => {
                    await this.getPoolsData(height)
                  }
                )
    } catch (error) {
      logger.error(
        `wallet beginStakeAcquisition ${error.stack || error}`
      )
    }
  }

  async getCoinPrice () {
    let coinPrice = 0
    try {
      logger.info("wallet getCoinPrice")
      const response = await axios.get(
        "https://api.coingecko.com/api/v3/coins/arqma?tickers=false&market_data=true&community_data=false&developer_data=false&sparkline=false\n"
      )
      const data = response.data
      coinPrice = data.market_data.current_price.usd
    } catch (error) {
      logger.error("wallet", "getCoinPrice", error.stack || error)
    } finally {
      this.sendGateway("set_coin_price", coinPrice)
    }
  }

  async removeSignatureData (ethereumAddress, blockNumber, signature) {
    try {
      logger.info("wallet removeSignatureData")
      if (this.subscriber !== null) {
        await this.subscriber.send([ethereumAddress, "COMPLETED", blockNumber, signature])
      }
    } catch (error) {
      logger.error("wallet", "Error in removeSignatureData:", error.stack || error)
    }
  }

  //   async subscribeForSignatureData (ethereumAddress) {
  //     try {
  //       logger.info("wallet subscribeForSignatureData")

  //       if (this.subscriber === null) {
  //         const context = new zmq.Context({ blocky: false })
  //         this.subscriber = new zmq.Dealer(context)
  //         this.subscriber.routingId = ethereumAddress
  //         // const address = "tcp://10.0.0.20:5556"
  //         // const address = "tcp://10.0.0.13:5556"
  //         const address = "tcp://154.38.161.92:5556"
  //         await this.subscriber.connect(address)

  //         await this.subscriber.send([ethereumAddress, "REGISTER"])

  //         const receiveObservable = new Observable(observer => {
  //           const receiveHandler = async () => {
  //             try {
  //               const [response] = await this.subscriber.receive()
  //               let signatures = []
  //               const responseString = response.toString()
  //               if (response.length > 0) {
  //                 signatures = JSON.parse(responseString)
  //               }
  //               observer.next(signatures)
  //               receiveHandler()
  //             } catch (error) {
  //               observer.error(error)
  //             }
  //           }
  //           receiveHandler()
  //           return async () => {
  //             await this.endSignatureSubscription()
  //           }
  //         })

  //         this.subscription = receiveObservable.subscribe({
  //           next: signatures => this.sendGateway("set_signature_data", signatures),
  //           error: async error => {
  //             console.error("Error in receiveObservable:", error)
  //             await this.endSignatureSubscription()
  //           }
  //         })
  //       }
  //     } catch (error) {
  //       logger.error("wallet", "Error in subscribeForSignatureData:", error.stack || error)
  //       await this.endSignatureSubscription()
  //     }
  //   }

  async getConversionData () {
    const conversionData = {
      sats: 0,
      currentPrice: 0.0
    }
    try {
      logger.info("wallet getConversionData")
      const actions = [
        axios.get("https://tradeogre.com/api/v1/ticker/BTC-ARQ"),
        axios.get("https://blockchain.info/ticker")
      ]

      const [conversionResponse, tickerResponse] =
                await Promise.allSettled(actions)
      if (conversionResponse.status === "fulfilled") {
        conversionData.sats = parseFloat(
          conversionResponse.value.data.price
        )
      }
      if (tickerResponse.status === "fulfilled") {
        conversionData.currentPrice =
                    tickerResponse.value.data.USD["15m"]
      }
    } catch (error) {
      logger.error("wallet", "getConversionData", error.stack || error)
    } finally {
      this.sendGateway("set_conversion_data", conversionData)
    }
  }

  async getPoolsData (height) {
    try {
      logger.info("wallet getPoolsData")
      let pools = {
        operator_pools: [],
        nonoperator_pools: [],
        staker: {
          stake: {
            burnt_xeq: 0,
            total_staked: 0,
            staked_nodes: 0,
            num_operating: 0,
            total_contributed: 0,
            active_pool_count: 0
          }
        }
      }

      const actions = [
        this.getPools(height)
      ]
      const [rpcPoolList] = await Promise.allSettled(actions)

      if (rpcPoolList && rpcPoolList.status === "fulfilled") {
        if (
          !rpcPoolList.value.hasOwnProperty("error") ||
                    rpcPoolList.value.hasOwnProperty("result")
        ) {
          pools = rpcPoolList.value
        }
      }
      this.sendGateway("set_pools_data", pools)
    } catch (error) {
      logger.error(`pools getPoolsData ${error.stack || error}`)
    }
  }

  isValidPasswordHash (password_hash) {
    try {
      logger.info("wallet  isValidPasswordHash")
      return (
        this.wallet_state.password_hash.toString("hex") ===
                password_hash.toString("hex")
      )
    } catch (error) {
      logger.error(`wallet isValidPasswordHash ${error.stack || error}`)
      return false
    }
  }

  hasPassword () {
    logger.info("wallet  hasPassword")
    try {
      if (this.wallet_state.password_hash === null) {
        this.sendGateway("set_has_password", false)
        return
      }

      if (!this.backend.config_data.app.promptForPassword) {
        this.sendGateway("set_has_password", true)
        return
      }

      const hashBuffer = crypto.pbkdf2Sync(
        "",
        this.auth[2],
        1000,
        64,
        "sha512"
      )
      // If the pass hash does match empty string then we have a password
      this.sendGateway(
        "set_has_password",
        this.wallet_state.password_hash.toString("hex") ===
                    hashBuffer.toString("hex")
      )
    } catch (error) {
      logger.error(`wallet hasPassword ${error.stack || error}`)
      this.sendGateway("set_has_password", false)
    }
  }

  async validateAddress (address) {
    try {
      logger.info("wallet  validateAddress")
      const data = await this.sendRPC("validate_address", {
        address
      })
      if (data && data.error) {
        this.sendGateway("set_valid_address", {
          address,
          valid: false
        })
        return
      }

      const { valid, nettype } = data.result

      const netMatches = this.net_type === nettype
      const isValid = valid && netMatches

      this.sendGateway("set_valid_address", {
        address,
        valid: isValid,
        nettype
      })
    } catch (error) {
      logger.error(`wallet validateAddress ${error.stack || error}`)
      this.sendGateway("set_valid_address", {
        address,
        valid: false
      })
    }
  }

  async createWallet (filename, password, language) {
    try {
      logger.info("wallet  createWallet")
      // Reset the status error
      this.sendGateway("reset_wallet_error")
      const data = await this.sendRPC("create_wallet", {
        filename,
        password,
        language
      })
      if (data && data.error) {
        this.sendGateway("set_wallet_error", { status: data.error })
        return
      }

      // store hash of the password so we can check against it later when requesting private keys, or for sending txs
      this.wallet_state.password_hash = crypto
        .pbkdf2Sync(password, this.auth[2], 1000, 64, "sha512")
        .toString("hex")
      this.wallet_state.name = filename
      this.wallet_state.open = true

      await this.finalizeNewWallet(filename)
    } catch (error) {
      logger.error(`wallet createWallet ${error.stack || error}`)
      this.sendGateway("set_wallet_error", {
        status: { code: 500, message: error.message }
      })
    }
  }

  async restoreWallet (
    filename,
    password,
    seed,
    refresh_type,
    refresh_start_timestamp_or_height
  ) {
    logger.info("wallet  restoreWallet")
    if (refresh_type === "date") {
      const date = new Date(refresh_start_timestamp_or_height)
      date.setHours(0, 0, 0, 0)
      const timestamp = Math.round(date.getTime() / 1000)

      refresh_start_timestamp_or_height =
                await this.backend.daemon.timestampToHeight(timestamp)
      if (refresh_start_timestamp_or_height === false) {
        this.sendGateway("set_wallet_error", {
          status: { code: -1, message: "Invalid restore date" }
        })
        return
      }
    }

    const restore_height = parseInt(refresh_start_timestamp_or_height)

    seed = seed.trim().replace(/\s{2,}/g, " ")

    this.sendGateway("reset_wallet_error")
    const data = await this.sendRPC("restore_deterministic_wallet", {
      filename,
      password,
      seed,
      restore_height
    })
    if (data.hasOwnProperty("error")) {
      this.sendGateway("set_wallet_error", { status: data.error })
      return
    }

    // store hash of the password so we can check against it later when requesting private keys, or for sending txs
    this.wallet_state.password_hash = crypto
      .pbkdf2Sync(password, this.auth[2], 1000, 64, "sha512")
      .toString("hex")
    this.wallet_state.name = filename
    this.wallet_state.open = true

    await this.finalizeNewWallet(filename)
  }

  async restoreViewWallet (
    filename,
    password,
    address,
    viewkey,
    refresh_type,
    refresh_start_timestamp_or_height
  ) {
    logger.info("wallet  restoreViewWallet")
    if (refresh_type === "date") {
      const date = new Date(refresh_start_timestamp_or_height)
      date.setHours(0, 0, 0, 0)
      const timestamp = Math.round(date.getTime() / 1000)

      refresh_start_timestamp_or_height =
                await this.backend.daemon.timestampToHeight(timestamp)
      if (refresh_start_timestamp_or_height === false) {
        this.sendGateway("set_wallet_error", {
          status: { code: -1, message: "Invalid restore date" }
        })
        return
      }
    }

    let refresh_start_height = refresh_start_timestamp_or_height

    if (!Number.isInteger(refresh_start_height)) {
      refresh_start_height = 0
    }

    const data = await this.sendRPC("generate_from_keys", {
      filename,
      password,
      address,
      viewkey,
      refresh_start_height
    })
    if (data.hasOwnProperty("error")) {
      this.sendGateway("set_wallet_error", { status: data.error })
      return
    }

    // store hash of the password so we can check against it later when requesting private keys, or for sending txs
    this.wallet_state.password_hash = crypto
      .pbkdf2Sync(password, this.auth[2], 1000, 64, "sha512")
      .toString("hex")
    this.wallet_state.name = filename
    this.wallet_state.open = true

    await this.finalizeNewWallet(filename)
  }

  async importWallet (filename, password, import_path) {
    logger.info("wallet  importWallet")
    // Reset the status error
    this.sendGateway("reset_wallet_error")

    // trim off suffix if exists
    if (import_path.endsWith(".keys")) {
      import_path = import_path.substring(
        0,
        import_path.length - ".keys".length
      )
    } else if (import_path.endsWith(".address.txt")) {
      import_path = import_path.substring(
        0,
        import_path.length - ".address.txt".length
      )
    }

    if (!existsSync(import_path)) {
      this.sendGateway("set_wallet_error", {
        status: { code: -1, message: "Invalid wallet path" }
      })
    } else {
      const destination = path.join(this.wallet_dir, filename)

      if (existsSync(destination) || existsSync(destination + ".keys")) {
        this.sendGateway("set_wallet_error", {
          status: {
            code: -1,
            message: "Wallet with name already exists"
          }
        })
        return
      }

      try {
        await copyFile(import_path, destination, fs.constants.COPYFILE_EXCL)

        if (existsSync(import_path + ".keys")) {
          await copyFile(
            import_path + ".keys",
            destination + ".keys",
            fs.constants.COPYFILE_EXCL
          )
        }
      } catch (e) {
        this.sendGateway("set_wallet_error", {
          status: { code: -1, message: "Failed to copy wallet" }
        })
        return
      }

      try {
        const data = await this.sendRPC("open_wallet", {
          filename,
          password
        })
        if (data.hasOwnProperty("error")) {
          if (existsSync(destination)) {
            await unlink(destination)
          }
          if (existsSync(destination + ".keys")) {
            await unlink(destination + ".keys")
          }

          this.sendGateway("set_wallet_error", {
            status: data.error
          })
          return
        }

        // store hash of the password so we can check against it later when requesting private keys, or for sending txs
        this.wallet_state.password_hash = crypto
          .pbkdf2Sync(password, this.auth[2], 1000, 64, "sha512")
          .toString("hex")
        this.wallet_state.name = filename
        this.wallet_state.open = true

        await this.finalizeNewWallet(filename)
      } catch (error) {
        this.sendGateway("set_wallet_error", {
          status: { code: -1, message: "An unknown error occured" }
        })
      }
    }
  }

  allSucceeded = (results) => {
    if (results.find((result) => result.status === "rejected")) {
      return false
    }
    return true
  }

  async finalizeNewWallet (filename) {
    logger.info("wallet  finalizeNewWallet")
    const info = {
      name: filename,
      address: "",
      balance: 0,
      unlocked_balance: 0,
      height: 0,
      view_only: false
    }

    const secret = {
      mnemonic: "",
      spend_key: "",
      view_key: ""
    }

    const [
      rpcAddress,
      rpcHeight,
      rpcBalance,
      rpcMnemoic,
      rpcSpendKey
      // rpcViewKey
    ] = await Promise.allSettled([
      this.sendRPC("get_address"),
      this.sendRPC("getheight"),
      this.sendRPC("getbalance", { account_index: 0 }),
      this.sendRPC("query_key", { key_type: "mnemonic" }),
      this.sendRPC("query_key", { key_type: "spend_key" })
      // this.sendRPC("query_key", { key_type: "view_key" })
    ])
    if (
      this.allSucceeded([
        rpcAddress,
        rpcHeight,
        rpcBalance,
        rpcMnemoic,
        rpcSpendKey
        // rpcViewKey
      ])
    ) {
      if (
        !rpcAddress.value.hasOwnProperty("error") ||
                rpcAddress.value.hasOwnProperty("result")
      ) {
        info.address = rpcAddress.value.result.address
        this.wallet_state.address = rpcAddress.value.result.address
      }
      if (
        !rpcHeight.value.hasOwnProperty("error") ||
                rpcHeight.value.hasOwnProperty("result")
      ) {
        info.height = rpcHeight.value.result.height
      }
      if (
        !rpcBalance.value.hasOwnProperty("error") ||
                rpcBalance.value.hasOwnProperty("result")
      ) {
        info.balance = rpcBalance.value.result.balance
        info.unlocked_balance =
                    rpcBalance.value.result.unlocked_balance
      }
      if (
        !rpcMnemoic.value.hasOwnProperty("error") ||
                rpcMnemoic.value.hasOwnProperty("result")
      ) {
        secret[rpcMnemoic.value.params.key_type] =
                    rpcMnemoic.value.result.key
        this.sendGateway("set_wallet_secret", secret)
      }
      if (
        !rpcSpendKey.value.hasOwnProperty("error") ||
                rpcSpendKey.value.hasOwnProperty("result")
      ) {
        if (/^0*$/.test(rpcSpendKey.value.result.key)) {
          info.view_only = true
        }
      }

      await this.saveWallet()
      const address_txt_path = path.join(
        this.wallet_dir,
        filename + ".address.txt"
      )
      if (!existsSync(address_txt_path)) {
        await writeFile(address_txt_path, info.address, "utf8")
        await this.listWallets()
      } else {
        await this.listWallets()
      }
    }
    this.sendGateway("set_wallet_info", info)

    this.startHeartbeat()
  }

  async openWallet (filename, password) {
    try {
      logger.info("wallet  openWallet")
      this.sendGateway("reset_wallet_error")
      let data = await this.sendRPC("open_wallet", {
        filename,
        password
      })
      if (data.hasOwnProperty("error")) {
        this.sendGateway("set_wallet_error", { status: data.error })
        return
      }

      const address_txt_path = path.join(
        this.wallet_dir,
        filename + ".address.txt"
      )
      if (!existsSync(address_txt_path)) {
        const data = await this.sendRPC("get_address", {
          account_index: 0
        })
        if (
          data.hasOwnProperty("error") ||
                    !data.hasOwnProperty("result")
        ) {
          return
        }
        await writeFile(address_txt_path, data.result.address, "utf8")
        await this.listWallets()
      }

      // store hash of the password so we can check against it later when requesting private keys, or for sending txs
      this.wallet_state.password_hash = crypto
        .pbkdf2Sync(password, this.auth[2], 1000, 64, "sha512")
        .toString("hex")
      this.wallet_state.name = filename
      this.wallet_state.open = true

      this.height_check = {
        address: 0,
        pools: 0,
        stake: 0,
        txs: 0
      }
      this.startHeartbeat()

      // Check if we have a view only wallet by querying the spend key
      data = await this.sendRPC("query_key", { key_type: "spend_key" })
      if (!data || data.hasOwnProperty("error") || !data.hasOwnProperty("result")) {
        return
      }
      if (/^0*$/.test(data.result.key)) {
        this.sendGateway("set_wallet_info", {
          view_only: true
        })
      }
    } catch (error) {
      logger.error(`wallet openWallet ${error.stack || error}`)
    }
  }

  async startHeartbeat () {
    try {
      logger.info("wallet  startHeartbeat")
      clearInterval(this.heartbeat)
      this.heartbeat = setInterval(
        async () => {
          await this.heartbeatAction()
        },
        this.local ? 5 * 1000 : 60 * 1000
      ) // 5 seconds for local daemon, 30 seconds for remote
      this.heartbeatAction(true)
    } catch (error) {
      logger.error(`wallet startHeartbeat ${error.stack || error}`)
    }
  }

  stopHeartbeat () {
    try {
      this.isRPCSyncing = false
      logger.info("wallet  stopHeartbeat")
      if (this.heartbeat) {
        clearInterval(this.heartbeat)
        this.heartbeat = null
      }
    } catch (error) {
      logger.error(`wallet stopHeartbeat ${error.stack || error}`)
    }
  }

  async heartbeatAction (extended = false) {
    try {
      // if (this.isRPCSyncing) {
      //   return
      // }
      logger.info("wallet  heartbeatAction")
      const info = {
        name: this.wallet_state.name
      }

      const [rpcAddress, rpcHeight, rpcBalance] =
                await Promise.allSettled([
                  this.sendRPC(
                    "get_address",
                    { account_index: 0 },
                    this.timeout
                  ),
                  this.sendRPC("getheight", {}, this.timeout),
                  this.sendRPC(
                    "getbalance",
                    { account_index: 0 },
                    this.timeout
                  )
                ])
      let hasHeightChange = false
      if (rpcHeight && rpcHeight.status === "fulfilled") {
        if (
          !rpcHeight.value.hasOwnProperty("error") ||
                    rpcHeight.value.hasOwnProperty("result")
        ) {
          hasHeightChange =
                        this.wallet_state.height !==
                        rpcHeight.value.result.height
          this.wallet_state.height = rpcHeight.value.result.height
          info.height = rpcHeight.value.result.height
        }
      }
      if (rpcAddress && rpcAddress.status === "fulfilled") {
        if (
          !rpcAddress.value.hasOwnProperty("error") ||
                    rpcAddress.value.hasOwnProperty("result")
        ) {
          info.address = rpcAddress.value.result.address
          this.wallet_state.address = rpcAddress.value.result.address
        }
      }
      let hasBalanceChange = false

      if (rpcBalance && rpcBalance.status === "fulfilled") {
        if (
          !rpcBalance.value.hasOwnProperty("error") ||
                    rpcBalance.value.hasOwnProperty("result")
        ) {
          // if balance has recently changed, get updated list of transactions and used addresses
          hasBalanceChange = !(
            this.wallet_state.balance ===
                            rpcBalance.value.result.balance &&
                        this.wallet_state.unlocked_balance ===
                            rpcBalance.value.result.unlocked_balance
          )
          if (hasBalanceChange) {
            this.wallet_state.balance = info.balance =
                            rpcBalance.value.result.balance
            this.wallet_state.unlocked_balance =
                            info.unlocked_balance =
                                rpcBalance.value.result.unlocked_balance
            const actions = [
              this.getTransactions(info.height),
              this.getAddressList(info.height)
            ]
            if (true || extended) {
              actions.push(this.getAddressBook())
            }

            const [
              rpcTransactions,
              rpcAddressList,
              rpcAddressBook
            ] = await Promise.allSettled(actions)

            if (
              rpcTransactions &&
                            rpcTransactions.status === "fulfilled"
            ) {
              if (
                !rpcTransactions.value.hasOwnProperty(
                  "error"
                ) ||
                                rpcTransactions.value.hasOwnProperty("result")
              ) {
                this.sendGateway(
                  "set_wallet_transactions",
                  rpcTransactions.value.transactions
                )
              }
            }

            if (
              rpcAddressList &&
                            rpcAddressList.status === "fulfilled"
            ) {
              if (
                !rpcAddressList.value.hasOwnProperty("error") ||
                                rpcAddressList.value.hasOwnProperty("result")
              ) {
                this.sendGateway(
                  "set_wallet_address_list",
                  rpcAddressList.value.address_list
                )
              }
            }

            if (
              extended &&
                            rpcAddressBook &&
                            rpcAddressBook.status === "fulfilled"
            ) {
              if (
                !rpcAddressBook.value.hasOwnProperty("error") ||
                                rpcAddressBook.value.hasOwnProperty("result")
              ) {
                this.sendGateway(
                  "set_wallet_address_book",
                  rpcAddressBook.value.address_list
                )
              }
            }
          }
        }
      }
      if (hasHeightChange || hasBalanceChange) {
        this.sendGateway("set_wallet_info", info)
        this.sendGateway("reset_wallet_status", {
          code: 0,
          message: "OK"
        })
      }
    } catch (error) {
      logger.error(`wallet heartbeatAction ${error.stack || error}`)
    }
  }

  async relayStake (origin) {
    try {
      logger.info("wallet  relayStake")
      const stakes = this.tx_metadata_list.filter(
        (item) => item.type === "stake"
      )
      let error = ""
      for (const stake of stakes) {
        const data = await this.sendRPC("relay_tx", {
          hex: stake.tx_metadata
        })
        if (data && data.hasOwnProperty("error")) {
          error = `${data.error.message
            .charAt(0)
            .toUpperCase()}${data.error.message.slice(1)}`
        }
        if (!!error) {
          this.sendGateway("set_tx_status", {
            code: -300,
            message: error,
            sending: false,
            origin
          })
          return
        }

        this.sendGateway("show_notification", {
          type: "positive",
          message: `Staked ${(
            stake.amount / this.coinUnits
          ).toLocaleString()} ARQ to: ${stake.service_node_key}`,
          timeout: 3000,
          origin
        })
        if (data.result.tx_hash) {
          await this.saveTxNotes(
            data.result.tx_hash,
            `Service Node: ${stake.service_node_key}`
          )
        }
      }
    } catch (error) {
      logger.error(`wallet relayStake ${error.stack || error}`)
      this.sendGateway("set_tx_status", {
        code: -300,
        message: "Failed to relay stake",
        sending: false,
        origin
      })
    } finally {
      this.tx_metadata_list = this.tx_metadata_list.filter(
        (item) => item.type !== "stake"
      ) // purge on success
    }
  }

  async stake (password, origin, amount, service_node_key, destination) {
    logger.info(`wallet  stake "password": ******, "key": ${service_node_key}, "destination": ${destination}, "amount": ${amount}`)
    const reply = {
      type: "",
      message: "",
      timeout: 3000,
      origin
    }
    try {
      let hashBuffer = ""
      this.tx_metadata_list = this.tx_metadata_list.filter(
        (item) => item.type === "stake"
      ) // purge previous stakes not relayed
      try {
        hashBuffer = this.promptForPasswordCheck(password)
      } catch (error) {
        reply.type = "negative"
        reply.message = "Pass Error"
        this.sendGateway("show_notification", reply)
        return
      }

      if (!this.isValidPasswordHash(hashBuffer)) {
        reply.type = "negative"
        reply.message = "Password Error"
        this.sendGateway("show_notification", reply)
        return
      }

      amount = parseFloat(amount).toFixed(9) * this.coinUnits
      const data = await this.sendRPC("stake", {
        amount,
        destination,
        service_node_key,
        do_not_relay: true,
        get_tx_metadata: true
      })
      if (data && data.hasOwnProperty("error")) {
        this.sendGateway("set_tx_status", {
          code: -300,
          message: `${data.error.message
            .charAt(0)
            .toUpperCase()}${data.error.message.slice(1)}`,
          sending: false
        })
        return
      }

      if (data.result) {
        const fee = data.result.fee / this.coinUnits
        this.tx_metadata_list.push({
          tx_metadata: data.result.tx_metadata,
          amount,
          service_node_key,
          type: "stake"
        }) // add new transactions
        this.sendGateway("set_tx_status", {
          code: 300,
          message: `Fee ${fee}`, // .toLocaleString()}`,
          sending: false
        })
      }
    } catch (error) {
      logger.error(`wallet stake ${error.stack || error}`)
      reply.type = "negative"
      reply.message = error.stack || error
      reply.timeout = 2000
      this.sendGateway("show_notification", reply)
    }
  }

  async registerSnode (password, register_service_node_str) {
    try {
      logger.info("wallet registerSnode")
      const hashBuffer = this.promptForPasswordCheck(password)
      if (!this.isValidPasswordHash(hashBuffer)) {
        this.sendGateway("set_snode_status", {
          registration: {
            code: -1,
            sending: false
          }
        })
        return
      }

      const data = await this.sendRPC("register_service_node", {
        register_service_node_str
      })
      if (data.hasOwnProperty("error")) {
        this.sendGateway("set_snode_status", {
          registration: {
            code: -1,
            message: `${data.error.message
              .charAt(0)
              .toUpperCase()}${data.error.message.slice(1)}`,
            sending: false
          }
        })
        return
      }

      this.sendGateway("set_snode_status", {
        registration: {
          code: 0,
          sending: false
        }
      })
    } catch (error) {
      logger.error(`wallet registerSnode ${error.stack || error}`)
      this.sendGateway("set_snode_status", {
        registration: {
          code: -1,
          sending: false
        }
      })
    }
  }

  async unlockStake (password, service_node_key, confirmed = false) {
    try {
      logger.info("wallet unlockStake")
      this.sendGateway("set_snode_status_unlock", { code: 0, message: "", sending: false }) // reset status
      const hashBuffer = this.promptForPasswordCheck(password)

      if (!this.isValidPasswordHash(hashBuffer)) {
        this.sendGateway("set_snode_status_unlock", {
          unlock: {
            code: -400,
            message: "invalidPassword",
            sending: false
          }
        })
        return
      }
      if (confirmed) {
        try {
          const data = await this.sendRPC("request_stake_unlock", {
            service_node_key
          })
          let unlock = {}
          if (data.result && typeof data.result === "object") {
            unlock = {
              code: data.result.unlocked ? -400 : -400,
              message: data.result.msg || "",
              sending: false
            }
          } else {
            unlock = {
              code: -400,
              message: (data.error && data.error.message) ? data.error.message : "Unknown error",
              sending: false
            }
          }
          this.sendGateway("set_snode_status_unlock", unlock)
        } catch (error) {
          logger.error(
            `wallet unlockStake:request_stake_unlock ${
              error.stack || error
            }`
          )
          this.sendGateway("set_snode_status_unlock", {
            code: -400,
            message: error.message,
            sending: false
          })
        }
      } else {
        try {
          const data = await this.sendRPC(
            "can_request_stake_unlock",
            { service_node_key }
          )
          let unlock = {}
          if (data.error) {
            unlock = {
              code: -400,
              message: data.error.message,
              sending: false
            }
          } else {
            unlock = {
              code: data.can_unlock ? 400 : -400,
              message: data.msg,
              sending: false
            }
          }
          this.sendGateway("set_snode_status_unlock", unlock)
        } catch (error) {
          logger.error(
            `wallet unlockStake:can_request_stake_unlock ${
              error.stack || error
            }`
          )
          this.sendGateway("set_snode_status_unlock", {
            code: -400,
            message: error.message,
            sending: false
          })
        }
      }
    } catch (error) {
      logger.error(`wallet unlockStake ${error.stack || error}`)
    }
  }

  async relaySweepAll (origin) {
    try {
      logger.info("wallet  relaySweepAll")
      const transfers = this.tx_metadata_list.filter(
        (item) => item.type === "sweepAll"
      )
      let error = ""
      for (const transfer of transfers) {
        const data = await this.sendRPC("relay_tx", {
          hex: transfer.tx_metadata
        })
        if (data && data.hasOwnProperty("error")) {
          error = `${data.error.message
            .charAt(0)
            .toUpperCase()}${data.error.message.slice(1)}`
          break
        }
      }

      if (!!error) {
        this.sendGateway("set_tx_status", {
          code: -100,
          message: error,
          sending: false,
          origin
        })
        return
      }

      this.sendGateway("set_tx_status", {
        code: 200,
        message: "SweepAll transaction successfully sent",
        sending: false,
        origin
      })
    } catch (error) {
      logger.error(`wallet relaySweepAll ${error.stack || error}`)
    } finally {
      this.tx_metadata_list = this.tx_metadata_list.filter(
        (item) => item.type !== "sweepAll"
      ) // purge
    }
  }

  async cancelTransaction (type) {
    try {
      logger.info("wallet cancelTransaction")
      this.tx_metadata_list = this.tx_metadata_list.filter(
        (item) => item.type !== type
      )
    } catch (error) {
      logger.error(`wallet cancelTransaction ${error.stack || error}`)
    }
  }

  promptForPasswordCheck (password) {
    if (password === null) { password = "" }
    if (!this.backend.config_data.app.promptForPassword) {
      return this.wallet_state.password_hash
    }
    return crypto.pbkdf2Sync(password, this.auth[2], 1000, 64, "sha512")
  }

  async sweepAll (password, origin, do_not_relay = false) {
    logger.info("wallet  sweepAll")
    const reply = {
      code: -100,
      message: "",
      sending: false,
      origin
    }
    try {
      const hashBuffer = this.promptForPasswordCheck(password)
      this.tx_metadata_list = this.tx_metadata_list.filter(
        (item) => item.type !== "sweepAll"
      ) // purge existing attempts
      if (!this.isValidPasswordHash(hashBuffer)) {
        reply.code = -100
        reply.message = "Invalid password"
      } else {
        let data = await this.sendRPC("get_address", {
          account_index: 0
        })
        if (
          data.hasOwnProperty("error") ||
                    !data.hasOwnProperty("result")
        ) {
          reply.message = data.error
        } else {
          const my_address = data.result.address
          const rpc_endpoint = "sweep_all"
          const params = {
            address: my_address,
            account_index: 0,
            priority: 0,
            ring_size: 16,
            do_not_relay,
            get_tx_metadata: true,
            get_tx_hex: true
          }

          data = await this.sendRPC(rpc_endpoint, params)
          if (data.hasOwnProperty("error")) {
            reply.message = `${data.error.message
              .charAt(0)
              .toUpperCase()}${data.error.message.slice(1)}`
          } else {
            let message = "sweep_all_rpc_success_message"
            if (do_not_relay) {
              const totalFees = data.result.fee_list.reduce(
                (sum, value) => sum + value,
                0
              )
              message = `${parseFloat(totalFees / this.coinUnits).toFixed(9)}`
              for (const item of data.result.tx_metadata_list) {
                this.tx_metadata_list.push({
                  tx_metadata: item,
                  tx_hash: data.result.tx_hash_list[0],
                  type: "sweepAll"
                }) // add new transactions
              }
            }

            reply.code = do_not_relay ? 99 : 100
            reply.message = message
          }
        }
      }
    } catch (error) {
      logger.error(`wallet sweepAll ${error.stack || error}`)
      reply.code = -100
      reply.message = "Internal error"
      reply.sending = false
    }
    this.sendGateway("set_tx_status", reply)
  }

  async relayTransfer () {
    try {
      logger.info("wallet  relayTransfer")
      const transfers = this.tx_metadata_list.filter(
        (item) => item.type === "transfer_split"
      )
      let error = ""
      for (const transfer of transfers) {
        const data = await this.sendRPC("relay_tx", {
          hex: transfer.tx_metadata
        })
        if (data && data.hasOwnProperty("error")) {
          error = `${data.error.message
            .charAt(0)
            .toUpperCase()}${data.error.message.slice(1)}`
          break
        }
        if (data.result.tx_hash) {
          this.saveTxNotes(data.result.tx_hash, transfer.note)
        }
      }

      if (!!error) {
        this.sendGateway("set_tx_status", {
          code: -200,
          message: error,
          sending: false
        })
        return
      }

      this.sendGateway("set_tx_status", {
        code: 201,
        message: "Transaction successfully sent",
        sending: false
      })
    } catch (error) {
      logger.error(`wallet relayTransfer ${error.stack || error}`)
    } finally {
      this.tx_metadata_list = this.tx_metadata_list.filter(
        (item) => item.type !== "transfer_split"
      )
    }
  }

  async transfer (
    password,
    amount,
    address,
    payment_id,
    priority,
    currency,
    note,
    address_book = {},
    memo,
    network
  ) {
    logger.info("wallet  transfer")
    const reply = {
      code: -200,
      message: "Internal error",
      sending: false
    }
    try {
      const hashBuffer = this.promptForPasswordCheck(password)
      this.tx_metadata_list = this.tx_metadata_list.filter(
        (item) => item.type !== "transfer_split"
      ) // purge
      if (!this.isValidPasswordHash(hashBuffer)) {
        reply.code = -200
        reply.message = "Invalid password"
        reply.sending = false
      } else {
        amount = parseFloat(amount).toFixed(9) * this.coinUnits
        const rpc_endpoint = "transfer_split"
        const params = {
          destinations: [{ amount, address }],
          priority,
          ring_size: 16
        }

        if (memo) {
          const memo_field = {
            network: 0,
            address: "",
            amount: ""
          }
          memo_field.address = memo
          memo_field.amount = amount.toString()
          memo_field.network = network
          params.memo = JSON.stringify(memo_field)
        }

        params.do_not_relay = true
        params.get_tx_metadata = true
        const data = await this.sendRPC(rpc_endpoint, params)
        if (data.hasOwnProperty("error")) {
          reply.code = -200
          reply.message = `${data.error.message
            .charAt(0)
            .toUpperCase()}${data.error.message.slice(1)}`
          reply.sending = false
        } else {
          if (data.result) {
            for (const item of data.result.tx_metadata_list) {
              this.tx_metadata_list.push({
                tx_metadata: item,
                amount,
                note,
                type: "transfer_split"
              }) // add new transactions
            }
            reply.message =
                            "Fee " +
                            (data.result.fee_list[0] / this.coinUnits) // .toLocaleString()
            reply.code = 200
          }

          if (
            address_book.hasOwnProperty("save") &&
                        address_book.save
          ) {
            this.addAddressBook(
              address,
              payment_id,
              address_book.description,
              address_book.name
            )
          }
        }
      }
    } catch (error) {
      logger.error(`wallet transfer ${error.stack || error}`)
      reply.code = -200
      reply.message = "Internal error"
      reply.sending = false
    }
    this.sendGateway("set_tx_status", reply)
  }

  rescanBlockchain () {
    try {
      logger.info("wallet  rescanBlockchain")
      this.sendRPC("rescan_blockchain")
    } catch (error) {
      logger.error(`wallet rescanBlockchain ${error.stack || error}`)
    }
  }

  rescanSpent () {
    try {
      logger.info("wallet  rescanSpent")
      this.sendRPC("rescan_spent")
    } catch (error) {
      logger.error(`wallet rescanSpent ${error.stack || error}`)
    }
  }

  async getPrivateKeys (password) {
    try {
      logger.info("wallet  getPrivateKeys")
      const secret = {
        mnemonic: "",
        spend_key: "",
        view_key: ""
      }

      try {
        const hashBuffer = this.promptForPasswordCheck(password)
        if (!this.isValidPasswordHash(hashBuffer)) {
          secret.mnemonic = "Invalid password"
          secret.spend_key = -1
          secret.view_key = -1
          this.sendGateway("set_wallet_secret", secret)
          return
        }
        const data = await Promise.all([
          this.sendRPC("query_key", { key_type: "mnemonic" }),
          this.sendRPC("query_key", { key_type: "spend_key" }),
          this.sendRPC("query_key", { key_type: "view_key" })
        ])
        for (const n of data) {
          if (
            n.hasOwnProperty("error") ||
                        !n.hasOwnProperty("result")
          ) {
            continue
          }
          secret[n.params.key_type] = n.result.key
        }
      } catch (error) {
        secret.mnemonic = "Internal error"
        secret.spend_key = -1
        secret.view_key = -1
      }
      this.sendGateway("set_wallet_secret", secret)
    } catch (error) {
      logger.error(`wallet getPrivateKeys ${error.stack || error}`)
    }
  }

  async getAddressList (height) {
    logger.info("wallet  getAddressList")
    const wallet = {
      info: {
        address: "",
        balance: 0,
        unlocked_balance: 0
      },
      address_list: {
        primary: [],
        used: [],
        unused: []
      }
    }
    try {
      const check = await this.checkHeight("address", height)
      if (!check) {
        return wallet
      }
      const [rpcAddress, rpcBalance] = await Promise.all([
        this.sendRPC("get_address", { account_index: 0 }),
        this.sendRPC("getbalance", { account_index: 0 })
      ])

      if (
        rpcBalance.hasOwnProperty("error") ||
                !rpcBalance.hasOwnProperty("result")
      ) {
        return wallet
      }
      if (
        rpcAddress.hasOwnProperty("error") ||
                !rpcAddress.hasOwnProperty("result")
      ) {
        return wallet
      }

      const num_unused_addresses = 10

      wallet.info.address = rpcAddress.result.address
      wallet.info.balance = rpcBalance.result.balance
      wallet.info.unlocked_balance = rpcBalance.result.unlocked_balance

      for (const address of rpcAddress.result.addresses) {
        address.balance = null
        address.unlocked_balance = null
        address.num_unspent_outputs = null

        if (rpcBalance.result.hasOwnProperty("per_subaddress")) {
          for (const address_balance of rpcBalance.result
            .per_subaddress) {
            if (
              address_balance.address_index ===
                            address.address_index
            ) {
              address.num_unspent_outputs = address_balance.num_unspent_outputs
              address.balance = address_balance.balance
              address.unlocked_balance = address_balance.unlocked_balance
              break
            }
          }
        }

        if (address.address_index === 0) {
          wallet.address_list.primary.push(address)
        } else if (address.used) {
          wallet.address_list.used.push(address)
        } else {
          wallet.address_list.unused.push(address)
        }
      }

      // limit to 10 unused addresses
      wallet.address_list.unused = wallet.address_list.unused.slice(
        0,
        10
      )

      if (
        wallet.address_list.unused.length < num_unused_addresses &&
                !wallet.address_list.primary[0].address.startsWith("RYoK") &&
                !wallet.address_list.primary[0].address.startsWith("RYoH")
      ) {
        for (
          let n = wallet.address_list.unused.length;
          n < num_unused_addresses;
          n++
        ) {
          const address = await this.sendRPC("create_address", {
            account_index: 0
          })
          wallet.address_list.unused.push(address.result)
        }
      }
    } catch (error) {
      logger.error(`wallet getAddressList ${error.stack || error}`)
    }
    return wallet
  }

  getUnLockTime (requested_unlock_height, height) {
    try {
      if (parseInt(requested_unlock_height) === 0) {
        return {
          amount: "",
          i18n: ""
        }
      }
      const blocks_remaining = parseInt(requested_unlock_height) - parseInt(height)
      if (blocks_remaining <= 0) {
        return {
          amount: "0",
          i18n: "components.pool_list_tabular.days"
        }
      }
      const days = Math.ceil(blocks_remaining / 720)
      return {
        amount: days.toString(),
        i18n: "components.pool_list_tabular.days"
      }
    } catch (error) {
      logger.error(`wallet getUnLockTime ${error.stack || error}`)
      return {
        amount: "0",
        i18n: "components.pool_list_tabular.days"
      }
    }
  }

  calculateOperatorFee (portions_for_operator) {
    let result = "0 %"
    try {
      if (portions_for_operator === 0) {
        return 0
      }
      const operator = new Decimal(portions_for_operator)
      if (operator === this.STAKING_SHARE_PARTS) return ""
      const amount = operator.div(this.STAKING_SHARE_PARTS).mul(100)
      if (amount.gte(100)) {
        result = ""
      } else {
        result = `${amount.toFixed(0)} %`
      }
    } catch (error) {
      logger.error(`wallet calculateOperatorFee ${error.stack || error}`)
    }
    return result
  }

  /*
  {
    "status": "fulfilled",
    "value": {
        "pool_list": [
        {
            "active": true,
            "contributors": [
            {
                "address": "ar3fceKHF5NEBmVRFJGuGofdFdbL73iVJXLwK8dY2ZfvPAmGJcpmoqL7FapikHyHtJUvzY63hCjWFLKGkeabVadi1qMatM8A9",
                "amount": 25000000000000,
                "locked_contributions": [
                {
                    "amount": 25000000000000,
                    "key_image": "bb584d9a4d40a1f2247ef18d979a3c2906d9d77d1c54d3fd4aaedf2e23be921f",
                    "key_image_pub_key": "c4d7bdcfffeef09e700a0513f26e71a3d5628dc9d615d20fc6f8c68ca1a90a55"
                }
                ],
                "reserved": 25000000000000
            },
            {
                "address": "ar3k85DeZBxBccvHouqaHnfvmZ4CVWLG5BC8JQ5F1bB1FhjGBz4qiV85jaNwgqXu7eQ9cB6dCvqVheZaFu97SNoe1FDsPih3K",
                "amount": 50000000000000,
                "locked_contributions": [
                {
                    "amount": 25000000000000,
                    "key_image": "402335c0eea07fdf320fbcf53276d8dde733dc1fe6b5f0da476f89c0fdbbd87d",
                    "key_image_pub_key": "4e29a17ec591c0e8530a8b38b0d181d48aabad5a19c5cfc11577ae3e3c44b64c"
                },
                {
                    "amount": 25000000000000,
                    "key_image": "c3a06ccb35b4ba9ccbbc953c2643ed83062bdba25e71d3f5dcc2ed38f79aaa02",
                    "key_image_pub_key": "1153a874e0c61766576977b0375c0885f9d11ab562094aee98f4d9c24ba66efb"
                }
                ],
                "reserved": 50000000000000
            },
            {
                "address": "ar3MrwFPvSxbMyJaMS6cEuSidLFKZuACVVB9NyExztNBTiLpbYCbEG8gx9V1P1pKht1tdHA1EzE71cjnBTgg6AXa1qpNyEcth",
                "amount": 25000000000000,
                "locked_contributions": [
                {
                    "amount": 25000000000000,
                    "key_image": "1339a55a628309256151f6c0d1771aadb50f9b282f56ff2cbe1c3e78dc55240f",
                    "key_image_pub_key": "6509146025ba4f40d6bf041276ff5c3dff0f42e707a48a9ad776d248d8148cc0"
                }
                ],
                "reserved": 25000000000000
            }
            ],
            "decommission_count": 0,
            "earned_downtime_blocks": 1,
            "funded": true,
            "last_reward_block_height": 1734387,
            "last_reward_transaction_index": 4294967295,
            "last_uptime_proof": 0,
            "operator_address": "ar3fceKHF5NEBmVRFJGuGofdFdbL73iVJXLwK8dY2ZfvPAmGJcpmoqL7FapikHyHtJUvzY63hCjWFLKGkeabVadi1qMatM8A9",
            "portions_for_operator": 3689348814741910500,
            "pubkey_ed25519": "",
            "pubkey_x25519": "",
            "public_ip": "80.0.0.0",
            "registration_height": 1734348,
            "requested_unlock_height": 1745153,
            "service_node_pubkey": "40ab33dc6fa06c0925e7b0a62e6d8699ae1de589ff88be9fe700c6cd7d41776d",
            "service_node_version": [
            0,
            0,
            0
            ],
            "staking_requirement": 100000000000000,
            "state_height": 1734368,
            "storage_port": 0,
            "storage_server_reachable": true,
            "storage_server_reachable_timestamp": 0,
            "swarm_id": 9223372036854776000,
            "total_contributed": 100000000000000,
            "total_reserved": 100000000000000,
            "version_major": 0,
            "version_minor": 0,
            "version_patch": 0,
            "votes": [
            {
                "height": 18446744073709552000,
                "voted": true
            },
            {
                "height": 18446744073709552000,
                "voted": true
            },
            {
                "height": 18446744073709552000,
                "voted": true
            },
            {
                "height": 18446744073709552000,
                "voted": true
            },
            {
                "height": 18446744073709552000,
                "voted": true
            },
            {
                "height": 18446744073709552000,
                "voted": true
            },
            {
                "height": 18446744073709552000,
                "voted": true
            },
            {
                "height": 18446744073709552000,
                "voted": true
            }
            ],
            "staked": "100,000",
            "equity": "50",
            "lockup": {
            "amount": "15",
            "i18n": "components.pool_list_tabular.days"
            },
            "available": "0",
            "is_contributor": true,
            "is_operator": false
        }
        ],
        "staker": {
        "stake": {
            "total_staked": 0,
            "staked_nodes": 5
        }
        }
    }
    }
  */
  async getPools (height) {
    logger.info("wallet  getPools")
    const pools = {
      operator_pools: [],
      nonoperator_pools: [],
      staker: {
        stake: {
          burnt_xeq: 0,
          total_staked: 0,
          staked_nodes: 0,
          num_operating: 0,
          total_contributed: 0,
          active_pool_count: 0
        }
      }
    }

    try {
      const check = await this.checkHeight("pools", height)
      if (!check) {
        return wallet
      }
      const data = await this.backend.daemon.sendRPC("get_service_nodes")
      if (!data.result) { return pools }
      if (!data.result.service_node_states) {
        data.result.service_node_states = []
      }
      const nonOperatorPools = []
      const operatorPools = []
      for (const pool of data.result.service_node_states) {
        pool.staked = (
          pool.total_contributed / this.coinUnits
        ).toLocaleString()
        pool.equity = ""
        pool.lockup = this.getUnLockTime(
          pool.requested_unlock_height,
          height
        )
        pool.available = (
          (pool.staking_requirement - pool.total_contributed) /
                    this.coinUnits
        ).toLocaleString()
        pool.operator_fee = this.calculateOperatorFee(pool.portions_for_operator)
        pools.staker.stake.total_contributed += pool.total_contributed / this.coinUnits
        pools.staker.stake.active_pool_count += pool.funded === true ? 1 : 0
        // Build a new object with only the fields you want to return
        const filteredPool = {
          service_node_pubkey: pool.service_node_pubkey,
          operator_address: pool.operator_address,
          staked: pool.staked,
          equity: "",
          lockup: pool.lockup,
          available: pool.available,
          operator_fee: pool.operator_fee,
          is_contributor: false,
          is_operator: false,
          contributors: pool.contributors.length,
          requested_unlock_height: pool.requested_unlock_height,
          last_reward_block_height: pool.last_reward_block_height,
          last_uptime_proof: pool.last_uptime_proof,
          staking_requirement: pool.staking_requirement,
          total_contributed: pool.total_contributed
        }

        if (pool.operator_address !== this.wallet_state.address) {
          if (
            pool.contributors.some(
              (k) => k.address === this.wallet_state.address
            )
          ) {
            const amount = pool.contributors
              .filter(
                (item) => item.address === this.wallet_state.address
              )
              .reduce(
                (accumulator, item) => accumulator + item.amount,
                0
              )
            filteredPool.equity = (
              (amount / pool.total_contributed) *
                        100
            ).toLocaleString()
            filteredPool.is_contributor = true
            filteredPool.is_operator = false
            pools.staker.stake.staked_nodes += 1
            nonOperatorPools.push(filteredPool)
          } else {
            filteredPool.is_contributor = false
            filteredPool.is_operator = false
            nonOperatorPools.push(filteredPool)
          }
        } else {
          const amount = pool.contributors
            .filter(
              (item) => item.address === this.wallet_state.address
            )
            .reduce(
              (accumulator, item) => accumulator + item.amount,
              0
            )
          pools.staker.stake.num_operating += 1
          pools.staker.stake.total_staked += amount / this.coinUnits
          pools.staker.stake.staked_nodes += 1
          filteredPool.equity = (
            (amount / pool.total_contributed) *
                        100
          ).toLocaleString()
          filteredPool.is_contributor = false
          filteredPool.is_operator = true
          operatorPools.push(filteredPool)
        }
      }
      pools.operator_pools = operatorPools.sort(this.poolListHeightSorter)
      pools.nonoperator_pools = nonOperatorPools.sort(this.poolListContributorSorter)
    } catch (error) {
      logger.error(`wallet getPools ${error.stack || error}`)
    }
    return pools
  }

  poolListHeightSorter (poolA, poolB) {
    try {
      if (poolA.registration_height === poolB.registration_height) {
        return 0
      }
      return poolA.registration_height > poolB.registration_height
        ? -1
        : 1
    } catch (error) {
      logger.error(`wallet poolListHeightSorter ${error.stack || error}`)
    }
  }

  poolListContributorSorter (poolA, poolB) {
    try {
    // Sort by is_contributor true first, then by registration_height descending
      if (poolA.is_contributor === poolB.is_contributor) {
        if (poolA.registration_height === poolB.registration_height) {
          return 0
        }
        return poolA.registration_height > poolB.registration_height ? -1 : 1
      }
      return poolA.is_contributor ? -1 : 1
    } catch (error) {
      logger.error(`wallet poolListContributorSorter ${error.stack || error}`)
      return 0
    }
  }

  async checkHeight (func_name, height) {
    logger.info("wallet  checkHeight")
    return new Promise((resolve, reject) => {
      resolve(true)
      // if (this.height_check[func_name] === height) {
      //     resolve(false)
      // } else {
      //     this.height_check[func_name] = height
      //     resolve(true)
      // }
    })
  }

  //   async getStake (address, height) {
  //     logger.info("wallet  getStake")
  //     const pools = {
  //       staker: {
  //         stake: {
  //           total_staked: 0,
  //           staked_nodes: []
  //         }
  //       }
  //     }
  //     try {
  //       const check = await this.checkHeight("stake", height)
  //       if (!check) {
  //         return pools
  //       }
  //       const data = await this.backend.daemon.sendRPC("on_get_staker", {
  //         address
  //       })
  //       Object.assign(pools.staker.stake, data.result)
  //       if (pools.staker.stake.total_staked === 0) {
  //         pools.staker.stake.staked_nodes = []
  //       }
  //     } catch (error) {
  //       logger.error(`pools getStake ${error.stack || error}`)
  //     }
  //     return pools
  //   }

  async exportTransactions (params) {
    logger.info("wallet  exportTransactions")
    const reply = {
      code: -99,
      message: "backend.transaction_export_failed",
      origin: "wallet_settings"
    }
    try {
      const hashBuffer = this.promptForPasswordCheck(params.password)
      if (!this.isValidPasswordHash(hashBuffer)) {
        reply.message = "backend.Invalid_password"
      } else {
        const allTransactions = await this.getTransactions(0, true)
        const filename = path.join(params.path, "transactions.csv")
        const writeStream = fs.createWriteStream(filename)
        for (
          let index = 0;
          index < allTransactions.transactions.tx_list.length;
          index++
        ) {
          const transaction = allTransactions.transactions.tx_list[index]
          delete transaction.subaddr_index
          delete transaction.subaddr_indices
          delete transaction.suggested_confirmations_threshold
          if (index === 0) {
            const headers = Object.keys(transaction)
            headers.splice(3, 0, "destinations")
            writeStream.write(headers.join("|") + "\n")
          } else {
            transaction.amount = transaction.amount / this.coinUnits
            if ("destinations" in transaction && transaction.destinations.length > 0) {
              transaction.destinations = JSON.stringify(transaction.destinations)
            }
            if (transaction.fee > 0) {
              transaction.fee = transaction.fee / this.coinUnits
            }
            transaction.timestamp = new Date(
              transaction.timestamp * 1000
            )
              .toLocaleString(undefined, {
                dateStyle: "short",
                timeStyle: "short"
              })
              .replace(",", "")
            const foo = Object.values(transaction)
            if (foo.length === 13) {
              foo.splice(3, 0, "[]")
            }
            writeStream.write(
              foo.join("|") + "\n"
            )
          }
        }
        writeStream.close()
        reply.code = 100
        reply.message = "backend.transaction_export_complete"
      }
    } catch (error) {
      logger.error(`wallet exportTransactions ${error.stack || error}`)
    }
    this.sendGateway("set_tx_status", reply)
  }

  /*
  {
      "id": 11,
      "jsonrpc": "2.0",
      "result": {
          "in": [
              {
                  "address": "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
                  "amount": 100000,
                  "confirmations": 5735,
                  "double_spend_seen": false,
                  "fee": 60,
                  "height": 972181,
                  "locked": false,
                  "note": "",
                  "payment_id": "0000000000000000",
                  "subaddr_index": {
                      "major": 0,
                      "minor": 0
                  },
                  "subaddr_indices": [
                      {
                          "major": 0,
                          "minor": 0
                      }
                  ],
                  "suggested_confirmations_threshold": 1,
                  "timestamp": 1669849369,
                  "txid": "85deb31f7f0420be5880f8fc87cedaf7765e6e582298a8819edaa77a3b3af3a0",
                  "type": "in",
                  "unlock_time": 0
              },
              {
                  "address": "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
                  "amount": 20000,
                  "confirmations": 22876,
                  "double_spend_seen": false,
                  "fee": 60,
                  "height": 955040,
                  "locked": false,
                  "note": "",
                  "payment_id": "0000000000000000",
                  "subaddr_index": {
                      "major": 0,
                      "minor": 0
                  },
                  "subaddr_indices": [
                      {
                          "major": 0,
                          "minor": 0
                      }
                  ],
                  "suggested_confirmations_threshold": 1,
                  "timestamp": 1667775540,
                  "txid": "46f6658e21b98ab1ce7377cd2bdb3cbd7b73b520a84b0b6e1ab9a63a4f99b3e9",
                  "type": "in",
                  "unlock_time": 0
              },
              {
                  "address": "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
                  "amount": 10000,
                  "confirmations": 39406,
                  "double_spend_seen": false,
                  "fee": 60,
                  "height": 938510,
                  "locked": false,
                  "note": "",
                  "payment_id": "0000000000000000",
                  "subaddr_index": {
                      "major": 0,
                      "minor": 0
                  },
                  "subaddr_indices": [
                      {
                          "major": 0,
                          "minor": 0
                      }
                  ],
                  "suggested_confirmations_threshold": 1,
                  "timestamp": 1665780950,
                  "txid": "795af73e6bcc1ca1a0420220f5468d1bbbe32587bc9837a61d581069d6bb0cef",
                  "type": "in",
                  "unlock_time": 0
              },
              {
                  "address": "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
                  "amount": 10000,
                  "confirmations": 39420,
                  "double_spend_seen": false,
                  "fee": 60,
                  "height": 938496,
                  "locked": false,
                  "note": "",
                  "payment_id": "0000000000000000",
                  "subaddr_index": {
                      "major": 0,
                      "minor": 0
                  },
                  "subaddr_indices": [
                      {
                          "major": 0,
                          "minor": 0
                      }
                  ],
                  "suggested_confirmations_threshold": 1,
                  "timestamp": 1665779414,
                  "txid": "d0d1b6d5d9c12182821abee10bbb3d39134c728bcf40fa368f7bb7d98955bc2b",
                  "type": "in",
                  "unlock_time": 0
              }
          ],
          "out": [
              {
                  "address": "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
                  "amount": 20000,
                  "confirmations": 5066,
                  "destinations": [
                      {
                          "address": "Tw1AXwU3z9kjMc5z21PaZ6HfQAJXmJbpWC6rdQtW7jw3Agp4t47UokKKTVkcXUTjYo4wtfu9nY87v1uJhKEpEpJv2DdeqLpwj",
                          "amount": 20000
                      }
                  ],
                  "double_spend_seen": false,
                  "fee": 60,
                  "height": 972850,
                  "locked": false,
                  "note": "",
                  "payment_id": "0000000000000000",
                  "subaddr_index": {
                      "major": 0,
                      "minor": 0
                  },
                  "subaddr_indices": [
                      {
                          "major": 0,
                          "minor": 0
                      }
                  ],
                  "suggested_confirmations_threshold": 1,
                  "timestamp": 1669929958,
                  "txid": "77124dd799b591e9575a33be59615f3b35179177dced1aca25cdc4f803f023cc",
                  "type": "out",
                  "unlock_time": 0
              },
              {
                  "address": "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
                  "amount": 0,
                  "confirmations": 5656,
                  "double_spend_seen": false,
                  "fee": 120,
                  "height": 972260,
                  "locked": false,
                  "note": "",
                  "payment_id": "0000000000000000",
                  "subaddr_index": {
                      "major": 0,
                      "minor": 0
                  },
                  "subaddr_indices": [
                      {
                          "major": 0,
                          "minor": 0
                      }
                  ],
                  "timestamp": 1669859685,
                  "txid": "62346aaeb5b800bade6d77575d7394c0d8293cb8b65a4b6d7278099d7f63a77b",
                  "type": "out",
                  "unlock_time": 0
              }
          ]
      },
      "params": {
          "in": true,
          "out": true,
          "pending": true,
          "failed": true,
          "pool": true
      }
  }

  */
  async getTransactions (height, applyFilter = true) {
    logger.info("wallet  getTransactions")
    const wallet = {
      transactions: {
        tx_list: []
      }
    }
    if (this.isQuitting) {
      return wallet
    }
    try {
      const check = await this.checkHeight("txs", height)
      if (!check) {
        return wallet
      }
      const windowBlocks = this.backend.config_data.app.daysOfTransactions * 720
      const filter_height = height > windowBlocks ? height - windowBlocks : 0
      const options = {
        in: true,
        out: true,
        pending: true,
        failed: true,
        pool: false,
        filter_by_height: applyFilter,
        min_height: filter_height
      }
      const data = await this.sendRPC("get_transfers", options)

      if (data && data.result) {
        const types = [
          "in",
          "out",
          "pending",
          "failed",
          "pool",
          "miner",
          "snode",
          "gov",
          "stake"
        ]
        types.forEach((type) => {
          if (data.result.hasOwnProperty(type)) {
            wallet.transactions.tx_list =
                            wallet.transactions.tx_list.concat(
                              data.result[type]
                            )
          }
        })

        for (let i = 0; i < wallet.transactions.tx_list.length; i++) {
          if (
            /^0*$/.test(wallet.transactions.tx_list[i].payment_id)
          ) {
            wallet.transactions.tx_list[i].payment_id = ""
          } else if (
            /^0*$/.test(
              wallet.transactions.tx_list[i].payment_id.substring(
                16
              )
            )
          ) {
            wallet.transactions.tx_list[i].payment_id =
                            wallet.transactions.tx_list[i].payment_id.substring(
                              0,
                              16
                            )
          }
        }

        wallet.transactions.tx_list.sort(function (a, b) {
          if (a.timestamp < b.timestamp) return 1
          if (a.timestamp > b.timestamp) return -1
          return 0
        })
      }
    } catch (error) {
      logger.error(`wallet getTransactions ${error.stack || error}`)
    }
    return wallet
  }

  async getTransactionByTxId (txid) {
    logger.info("wallet  getTransactionByTxId")
    let transfer = {}
    if (this.isQuitting) {
      return transfer
    }
    try {
      const options = {
        txid
      }

      const data = await this.sendRPC("get_transfer_by_txid", options)

      if (data && data.result) {
        transfer = data.result.transfer
      }
    } catch (error) {
      logger.error(`wallet getTransactionByTxId ${error.stack || error}`)
    }
    return transfer
  }

  /*
    {
        "address_list": {
            "address_book": [
                {
                    "address": "Tw1j56oPeHmfRb8UrqCG35JhABWhRJd9ycJiK2cfpUGw4HFpuDGHxXFAP71uXkjPN3JoKZzZ9oCFweRJxdZXsuxt2tnw1TNKZ",
                    "description": "",
                    "index": 0,
                    "starred": false,
                    "name": "test b wallet"
                }
            ],
            "address_book_starred": [
                {
                    "address": "Tsz58Nfvb4GbMvtZfGVQb5hyyZeU1NgkaHj9FUpbWhDzcd5hW4E2rdoS73sMQgDA4UiSEAfArNVBhHYQHgd61doU5TQuPs8kkc",
                    "description": "My TO account",
                    "index": 1,
                    "starred": true,
                    "name": "TradeOgre"
                }
            ]
        }
    }
*/
  async getAddressBook () {
    logger.info("wallet  getAddressBook")
    const wallet = {
      address_list: {
        address_book: [],
        address_book_starred: []
      }
    }
    try {
      const data = await this.sendRPC("get_address_book")
      if (data && data.result && data.result.entries) {
        for (let i = 0; i < data.result.entries.length; i++) {
          const entry = data.result.entries[i]
          const desc = entry.description.split("::")
          if (desc.length === 3) {
            entry.starred = desc[0] === "starred"
            entry.name = desc[1]
            entry.description = desc[2]
          } else if (desc.length === 2) {
            entry.starred = false
            entry.name = desc[0]
            entry.description = desc[1]
          } else {
            entry.starred = false
            entry.name = entry.description
            entry.description = ""
          }

          if (entry.payment_id) {
            if (/^0*$/.test(entry.payment_id)) {
              entry.payment_id = ""
            } else if (
              /^0*$/.test(entry.payment_id.substring(16))
            ) {
              entry.payment_id = entry.payment_id.substring(
                0,
                16
              )
            }
          }

          if (entry.starred) {
            wallet.address_list.address_book_starred.push(entry)
          } else {
            wallet.address_list.address_book.push(entry)
          }
        }
      }
    } catch (error) {
      logger.error(`wallet getAddressBook ${error.stack || error}`)
    }
    return wallet
  }

  async deleteAddressBook (index = false) {
    try {
      logger.info("wallet  deleteAddressBook")
      if (index !== false) {
        await this.sendRPC("delete_address_book", { index })
        await this.saveWallet()
        const data = await this.getAddressBook()
        if (data) {
          if (
            !data.hasOwnProperty("error") ||
                        data.hasOwnProperty("result")
          ) {
            this.sendGateway(
              "set_wallet_address_book",
              data.address_list
            )
          }
        }
      }
    } catch (error) {
      logger.error(`wallet deleteAddressBook ${error.stack || error}`)
    }
  }

  async addAddressBook (
    address,
    payment_id = null,
    description = "",
    name = "",
    starred = false,
    index = false
  ) {
    try {
      logger.info("wallet  addAddressBook")
      if (index !== false) {
        await this.sendRPC("delete_address_book", { index })
        await this.addAddressBook(
          address,
          payment_id,
          description,
          name,
          starred
        )
        return
      }

      const params = {
        address
      }
      if (payment_id != null) {
        params.payment_id = payment_id
      }

      let descriptor = ""
      if (!!params.description) { descriptor = `saved as ${params.description}` }
      const desc = []
      if (starred) {
        desc.push("starred")
      }
      desc.push(name, description)
      params.description = desc.join("::")
      let data = await this.sendRPC("add_address_book", params)
      if (data) {
        if (
          data.hasOwnProperty("error") ||
                    !data.hasOwnProperty("result")
        ) {
          logger.error(`wallet addAddressBook1 ${JSON.stringify(data.error)}`)
          this.sendGateway("show_notification", {
            type: "negative",
            message: "Wallet RPC Error, Address Rejected",
            timeout: 3000
          })
          return
        }
      }

      await this.saveWallet()
      data = await this.getAddressBook()
      if (data) {
        if (
          data.hasOwnProperty("error") ||
                    data.hasOwnProperty("result")
        ) {
          logger.error(`wallet addAddressBook2 ${JSON.stringify(data.error)}`)
        } else {
          this.sendGateway(
            "set_wallet_address_book",
            data.address_list
          )
          this.sendGateway("show_notification", {
            type: "positive",
            message: `Address Book updated with ${params.address} ${descriptor}`,
            timeout: 3000
          })
        }
      }
    } catch (error) {
      logger.error(`wallet addAddressBook ${error.stack || error}`)
    }
  }

  async saveTxNotes (txid, note) {
    logger.info("wallet  saveTxNotes")
    try {
      await this.sendRPC("set_tx_notes", {
        txids: [txid],
        notes: [note]
      })
      const rpcTransaction = await this.getTransactionByTxId(txid)
      if (rpcTransaction) {
        this.sendGateway(
          "set_wallet_transaction",
          rpcTransaction)
      }
    } catch (error) {
      logger.error(`wallet saveTxNotes ${error.stack || error}`)
    }
  }

  async exportKeyImages (password, filename = null, all) {
    logger.info("wallet  exportKeyImages")
    try {
      const hashBuffer = this.promptForPasswordCheck(password)
      if (!this.isValidPasswordHash(hashBuffer)) {
        this.sendGateway("show_notification", {
          type: "negative",
          message: "Invalid password",
          timeout: 3000
        })
        return
      }

      if (filename == null) {
        filename = path.join(
          this.wallet_data_dir,
          "images",
          this.wallet_state.name,
          "key_image_export"
        )
      } else {
        filename = path.join(filename, "key_image_export")
      }

      const directoryName = path.join(this.wallet_data_dir, "images", this.wallet_state.name)
      if (!existsSync(directoryName)) {
        mkdirSync(directoryName, { recursive: true })
      }

      try {
        const data = await this.sendRPC("export_key_images", { all })
        if (
          data.hasOwnProperty("error") ||
                    !data.hasOwnProperty("result")
        ) {
          this.sendGateway("show_notification", {
            type: "negative",
            message: "Error exporting key images",
            timeout: 3000
          })
          return
        }

        if (data.result.signed_key_images) {
          await writeFile(
            filename,
            JSON.stringify(data.result.signed_key_images),
            "utf-8"
          )
          this.sendGateway("show_notification", {
            message: "Key images exported to " + filename,
            timeout: 3000
          })
        } else {
          this.sendGateway("show_notification", {
            type: "warning",
            textColor: "black",
            message: "No key images found to export",
            timeout: 3000
          })
        }
      } catch (error) {
        logger.error(`wallet exportKeyImages ${error.stack || error}`)
        this.sendGateway("show_notification", {
          type: "negative",
          message: "Error exporting key images",
          timeout: 3000
        })
      }
    } catch (error) {
      logger.error(`wallet exportKeyImages ${error.stack || error}`)
      this.sendGateway("show_notification", {
        type: "negative",
        message: "Internal error",
        timeout: 3000
      })
    }
  }

  async importKeyImages (password, filename = null) {
    logger.info("wallet  importKeyImages")
    try {
      const hashBuffer = this.promptForPasswordCheck(password)
      if (!this.isValidPasswordHash(hashBuffer)) {
        this.sendGateway("show_notification", {
          type: "negative",
          message: "Invalid password",
          timeout: 3000
        })
        return
      }

      if (filename == null) {
        filename = path.join(
          this.wallet_data_dir,
          "images",
          this.wallet_state.name,
          "key_image_export"
        )
      }
      let signed_key_images = {}
      try {
        signed_key_images = JSON.parse(
          await readFile(filename, "utf-8")
        )
      } catch (error) {
        this.sendGateway("show_notification", {
          type: "negative",
          message: "Error parsing key images as JSON",
          timeout: 3000
        })
        return
      }
      const data = await this.sendRPC("import_key_images", {
        signed_key_images
      })
      if (
        data.hasOwnProperty("error") ||
                !data.hasOwnProperty("result")
      ) {
        logger.error(`wallet importKeyImages ${JSON.stringify(data.error)}`)
        this.sendGateway("show_notification", {
          type: "negative",
          message: "Error importing key images. change to local daemon",
          timeout: 3000
        })
        return
      }

      this.sendGateway("show_notification", {
        message: "Key images imported",
        timeout: 3000
      })
    } catch (error) {
      logger.error(`wallet importKeyImages ${error.stack || error}`)
      this.sendGateway("show_notification", {
        type: "negative",
        message: "Internal error",
        timeout: 3000
      })
    }
  }

  async copyOldGuiWallets (wallets) {
    try {
      logger.info("wallet  copyOldGuiWallets")
      this.sendGateway("set_old_gui_import_status", {
        code: 1,
        failed_wallets: []
      })

      const failed_wallets = []

      for (const wallet of wallets) {
        const { type, directory } = wallet

        const old_gui_path = path.join(this.wallet_dir, "old-gui")
        const dir_path = path.join(this.wallet_dir, directory)
        const stats = await stat(dir_path)
        if (!stats.isDirectory()) continue

        // Make sure the directory has the regular and keys file
        const wallet_file = path.join(dir_path, directory)
        const key_file = wallet_file + ".keys"

        // If we don't have them then don't bother copying
        if (!(existsSync(wallet_file) && existsSync(key_file))) {
          failed_wallets.push(directory)
          continue
        }

        // Copy out the file into the relevant directory
        const destination = path.join(this.dirs[type], "wallets")
        if (!existsSync(destination)) {
          await mkdir(destination, { recursive: true })
        }

        const new_path = path.join(destination, directory)

        try {
          // Copy into temp file
          if (
            existsSync(new_path + ".atom") ||
                        existsSync(new_path + ".atom.keys")
          ) {
            failed_wallets.push(directory)
            continue
          }

          await copyFile(
            wallet_file,
            new_path + ".atom",
            constants.COPYFILE_EXCL
          )
          await copyFile(
            key_file,
            new_path + ".atom.keys",
            constants.COPYFILE_EXCL
          )

          // Move the folder into a subfolder
          if (!existsSync(old_gui_path)) {
            await mkdir(old_gui_path, { recursive: true })
          }
          const destinationDir = path.join(old_gui_path, directory)
          await rmdir(destinationDir, {
            recursive: true,
            force: true
          })
          await rename(dir_path, destinationDir)
        } catch (e) {
          // Cleanup the copied files if an error
          if (existsSync(new_path + ".atom")) {
            await unlink(new_path + ".atom")
          }
          if (existsSync(new_path + ".atom.keys")) {
            await unlink(new_path + ".atom.keys")
          }
          failed_wallets.push(directory)
          continue
        }

        // Rename the imported wallets if we can
        if (!existsSync(new_path) && !existsSync(new_path + ".keys")) {
          await rename(new_path + ".atom", new_path)
          await rename(new_path + ".atom.keys", new_path + ".keys")
        }
      }

      this.sendGateway("set_old_gui_import_status", {
        code: 0,
        failed_wallets
      })
      await this.listWallets()
    } catch (error) {
      logger.error(`wallet copyOldGuiWallets ${error.stack || error}`)
    }
  }

  async listWallets (legacy = false) {
    try {
      logger.info("wallet  listWallets")
      const wallets = {
        list: [],
        directories: []
      }

      const filenames = await readdir(this.wallet_dir)
      for (const filename of filenames) {
        switch (filename) {
          case ".DS_Store":
          case ".DS_Store?":
          case "._.DS_Store":
          case ".Spotlight-V100":
          case ".Trashes":
          case "ehthumbs.db":
          case "Thumbs.db":
          case "old-gui":
            continue
        }

        // If it's a directory then check if it's an old gui wallet
        const name = path.join(this.wallet_dir, filename)
        const stats = await stat(name)
        if (stats.isDirectory()) {
          // Make sure the directory has the regular and keys file
          const wallet_file = path.join(name, filename)
          const key_file = wallet_file + ".keys"

          // If we have them then it is an old gui wallet
          if (existsSync(wallet_file) && existsSync(key_file)) {
            wallets.directories.push(filename)
          }
          continue
        }
        if (path.extname(filename) !== "") continue

        const wallet_data = {
          name: filename,
          address: null,
          password_protected: null
        }

        const metaFile = path.join(
          this.wallet_dir,
          filename + ".meta.json"
        )
        if (existsSync(metaFile)) {
          const fileContent = await readFile(metaFile, "utf8")
          if (fileContent) {
            const meta = JSON.parse(fileContent)
            wallet_data.address = meta.address
            wallet_data.password_protected =
                            meta.password_protected
          }
        }
        const addressFile = path.join(
          this.wallet_dir,
          filename + ".address.txt"
        )
        if (existsSync(addressFile)) {
          const fileContent = await readFile(addressFile, "utf8")
          if (fileContent) {
            wallet_data.address = fileContent
          }
        }
        wallets.list.push(wallet_data)
      }

      // Check for legacy wallet files
      if (legacy) {
        wallets.legacy = []
        let legacy_paths = []
        if (os.platform() === "win32") {
          legacy_paths = ["C:\\ProgramData\\arqma"]
        } else {
          legacy_paths = [path.join(os.homedir(), "arqma")]
        }
        for (let i = 0; i < legacy_paths.length; i++) {
          let legacy_config_path = path.join(
            legacy_paths[i],
            "config",
            "wallet_info.json"
          )
          if (this.net_type === "test") {
            legacy_config_path = path.join(
              legacy_paths[i],
              "testnet",
              "config",
              "wallet_info.json"
            )
          }
          if (!existsSync(legacy_config_path)) {
            continue
          }

          const legacy_config = JSON.parse(
            await readFile(legacy_config_path, "utf8")
          )
          const legacy_wallet_path = legacy_config.wallet_filepath
          if (!existsSync(legacy_wallet_path)) {
            continue
          }

          let legacy_address = ""
          if (existsSync(legacy_wallet_path + ".address.txt")) {
            legacy_address = await readFile(
              legacy_wallet_path + ".address.txt",
              "utf8"
            )
          }
          wallets.legacy.push({
            path: legacy_wallet_path,
            address: legacy_address
          })
        }
      }
      this.sendGateway("wallet_list", wallets)
    } catch (error) {
      logger.error(`wallet listWallets ${error.stack || error}`)
    }
  }

  async changeWalletPassword (old_password, new_password) {
    logger.info("wallet  changeWalletPassword")
    try {
      const hashBuffer = crypto.pbkdf2Sync(
        old_password,
        this.auth[2],
        1000,
        64,
        "sha512"
      )
      if (!this.isValidPasswordHash(hashBuffer)) {
        this.sendGateway("show_notification", {
          type: "negative",
          message: "Invalid old password",
          timeout: 3000
        })
        return
      }

      const data = await this.sendRPC("change_wallet_password", {
        old_password,
        new_password
      })
      if (
        data.hasOwnProperty("error") ||
                !data.hasOwnProperty("result")
      ) {
        this.sendGateway("show_notification", {
          type: "negative",
          message: "Error changing password",
          timeout: 3000
        })
        return
      }

      // store hash of the password so we can check against it later when requesting private keys, or for sending txs
      this.wallet_state.password_hash = crypto
        .pbkdf2Sync(new_password, this.auth[2], 1000, 64, "sha512")
        .toString("hex")

      this.sendGateway("show_notification", {
        message: "Password updated",
        timeout: 3000
      })
    } catch (error) {
      logger.error(`wallet changeWalletPassword ${error.stack || error}`)
      this.sendGateway("show_notification", {
        type: "negative",
        message: "Internal error",
        timeout: 3000
      })
    }
  }

  async deleteWallet (password) {
    logger.info("wallet  deleteWallet")
    try {
      const hashBuffer = crypto.pbkdf2Sync(
        password || "",
        this.auth[2],
        1000,
        64,
        "sha512"
      )
      if (!this.isValidPasswordHash(hashBuffer)) {
        this.sendGateway("show_notification", {
          type: "negative",
          message: "Invalid password",
          timeout: 3000
        })
        return
      }

      this.sendGateway("show_loading", { message: "Deleting wallet" })

      const wallet_path = path.join(
        this.wallet_dir,
        this.wallet_state.name
      )
      await this.closeWallet()
      await unlink(wallet_path)
      await unlink(wallet_path + ".keys")
      await unlink(wallet_path + ".address.txt")

      await this.listWallets()
      this.sendGateway("hide_loading")
      this.sendGateway("return_to_wallet_select")
    } catch (error) {
      logger.error(`wallet deleteWallet ${error.stack || error}`)
      this.sendGateway("show_notification", {
        type: "negative",
        message: "Internal error",
        timeout: 3000
      })
    }
  }

  async saveWallet () {
    logger.info("wallet  saveWallet")
    try {
      await this.sendRPC("store", {}, this.timeout)
    } catch (error) {
      logger.error(`wallet saveWallet ${error.stack || error}`)
    }
  }

  async closeWallet () {
    logger.info("wallet  closeWallet")
    this.wallet_state = {
      open: false,
      name: "",
      password_hash: null,
      balance: null,
      unlocked_balance: null
    }
    try {
      this.stopHeartbeat()
      await this.saveWallet()
      await this.endSignatureSubscription()
    } catch (error) {
      logger.error(
        `wallet closeWallet/saveWallet ${error.stack || error}`
      )
    }
    try {
      await this.sendRPC("close_wallet", {}, this.timeout)
    } catch (error) {
      logger.error(`wallet closeWallet ${error.stack || error}`)
    } finally {
    }
  }

  sendGateway (method, data) {
    // if wallet is closed, do not send any wallet data to gateway
    // this is for the case that we close the wallet at the same
    // after another action has started, but before it has finished
    try {
      if (!this.wallet_state.open && method.startsWith("set_") && method !== "set_wallet_error") {
        return
      }
      if (this.backend) { this.backend.send(method, data) }
    } catch (error) {
      logger.error(`wallet sendGateway ${error.stack || error}`)
    }
  }

  parseWalletResponse (res, params) {
    if (res.status === 200) {
      if ("result" in res.data) {
        res.data.params = params
        return res.data
      } else {
        const error = new Error("RPC Error!")
        error.code = res.data.error.code
        error.message = res.data.error.message
        throw error
      }
    } else {
      logger.error(
        `wallet, parseWalletResponse, ${JSON.stringify(res.error)}`
      )
      const error = new Error("HTTP Error!")
      error.code = res.status
      error.message = res.error
      throw error
    }
  }

  async sendRPC (method, params = {}, timeout = 0) {
    if (this.isQuitting) {
      if (method !== "store" && method !== "close_wallet") {
        return
      }
    }
    const id = this.id++
    const options = {
      jsonrpc: "2.0",
      id,
      method
    }
    if (Object.keys(params).length !== 0) {
      options.params = params
    }
    if (timeout > 0) {
      options.timeout = timeout
    }

    const maxRetries = 3
    const timeoutMs = timeout > 0 ? timeout : 30000 // fallback to 10s if not set

    return this.queue.add(async () => {
      for (let attempt = 1; attempt <= maxRetries; attempt++) {
        if (this.isQuitting) {
          return
        }
        try {
          const response = await Promise.race([
            this.axiosDigest.post(
                `${this.protocol}${this.hostname}:${this.port}/json_rpc`,
                options
            ),
            new Promise((resolve, reject) =>
              setTimeout(() => reject(new Error("RPC request timed out")), timeoutMs)
            )
          ])
          const result = this.parseWalletResponse(response, params)
          return result
        } catch (error) {
          logger.error(`wallet, sendRPC, ${JSON.stringify(options, null, 2)} attempt: ${attempt} ${JSON.stringify(error)}`)
          if (attempt === maxRetries) {
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

  //   async sendRPC (method, params = {}, timeout = 0) {
  //     if (this.isQuitting) {
  //       if (method !== "store" && method !== "close_wallet") {
  //         return
  //       }
  //     }
  //     const id = this.id++
  //     const options = {
  //       jsonrpc: "2.0",
  //       id,
  //       method
  //     }
  //     if (Object.keys(params).length !== 0) {
  //       options.params = params
  //     }
  //     if (timeout > 0) {
  //       options.timeout = timeout
  //     }
  //     return this.queue.add(async () => {
  //       try {
  //         const response = await this.axiosDigest.post(
  //           `${this.protocol}${this.hostname}:${this.port}/json_rpc`,
  //           options
  //         )
  //         const result = this.parseWalletResponse(response, params)
  //         return result
  //       } catch (error) {
  //         return {
  //           method,
  //           params,
  //           error: {
  //             code: error.code ? error.code : "",
  //             message: error.message,
  //             cause: error.code ? error.code : ""
  //           }
  //         }
  //       }
  //     })
  //   }

  getRPC (parameter, params = {}) {
    return this.sendRPC(`get_${parameter}`, params)
  }

  async quit () {
    logger.info("wallet  quit")
    this.isQuitting = true
    this.stopHeartbeat()
    this.endStakeAcquisition()
    this.backend = null
    for (
      let index = this.walletRPCProcesses.length - 1;
      index >= 0;
      index--
    ) {
      const walletRPCProcess = this.walletRPCProcesses[index]
      await this.closeWallet()
      walletRPCProcess.kill("SIGKILL")
    }
  }
}
