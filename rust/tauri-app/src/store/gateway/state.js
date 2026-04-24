export default {
  notifier: { save: false },
  app: {
    status: {
      code: 1 // Connecting to backend
    },
    config: {
      appearance: {
        theme: "dark"
      },
      pool: {
        server: { enabled: false, bindIP: "", bindPort: 3333 },
        mining: { address: "", enableBlockRefreshInterval: false, blockRefreshInterval: 5, minerTimeout: 900, uniform: true },
        varDiff: { enabled: true, startDiff: 5000, minDiff: 1000, maxDiff: 1000000, targetTime: 45, retargetTime: 60, variancePercent: 45, maxJump: 30, fixedDiffSeparator: "." }
      }
    },
    pending_config: {},
    selected_node: "",
    scan: false,
    remotes: [],
    net_type: "local",
    promptForPassword: true,
    loggingLevel: "info",
    daysOfTransactions: 1,
    inactivityTimeout: 5
  },
  ethereum: {},
  wallets: {
    list: [],
    legacy: [],

    // List of wallets that are in a sub folder (format of the old GUI)
    directories: []
  },
  old_gui_import_status: {
    code: 0, // Success
    failed_wallets: []
  },
  wallet: {
    status: {
      code: 1,
      message: null
    },
    info: {
      name: "",
      address: "",
      height: 0,
      balance: 0,
      unlocked_balance: 0,
      view_only: false
    },
    secret: {
      mnemonic: "",
      view_key: "",
      spend_key: ""
    },
    transactions: {
      tx_list: []
    },
    address_list: {
      used: [],
      unused: [],
      address_book: []
    }
  },
  pools: {
    operator_pools: [],
    nonoperator_pools: [],
    staker: {
      stake: {}
    }
  },
  pool: {
    status: 0,
    desynced: false,
    system_clock_error: false,
    stats: {
      currentEffort: 0,
      roundHashes: 0,
      blockTime: 0,
      blocksFound: 0,
      averageEffort: 0,
      networkHashrate: 0,
      diff: 0,
      height: 0
    },
    blocks: [],
    workers: [
      {
        miner: "all",
        active: true,
        lastShare: 0,
        hashes: 0,
        hashrate_5min: 0,
        hashrate_1hr: 0,
        hashrate_6hr: 0,
        hashrate_24hr: 0,
        hashrate_graph: {}
      }
    ]
  },
  tx_status: {
    code: 0,
    message: "",
    sending: false
  },
  /** `sweep_all_progress` from Tauri during `sweepAll` (output count + long RPC wait). */
  sweep_all_progress: null,
  service_node_status: {
    stake: {
      code: 0,
      message: "",
      sending: false
    },
    registration: {
      code: 0,
      message: "",
      sending: false
    },
    unlock: {
      code: 0,
      message: "",
      sending: false
    }
  },
  daemon: {
    info: {
      alt_blocks_count: 0,
      cumulative_difficulty: 0,
      difficulty: 0,
      grey_peerlist_size: 0,
      height: 0,
      height_without_bootstrap: 0,
      incoming_connections_count: 0,
      is_ready: false,
      outgoing_connections_count: 0,
      status: "OK",
      target: 240,
      target_height: 0,
      testnet: false,
      top_block_hash: null,
      tx_count: 0,
      tx_pool_size: 0,
      white_peerlist_size: 0
    },
    connections: [],
    bans: [],
    tx_pool_backlog: [],
    selected_node: ""
  },
  daemon_version: "",
  coin_price: 0,
  pools_filter: { index: 1, label: "pages.wallet.staking_pools.open", description: "pages.wallet.staking_pools.open_description", value: (c) => c.total_contributed < c.staking_requirement },
  node_id_filter: { index: 3, label: "Transaction", value: "" },
  operator_id_filter: { index: 4, label: "Operator", value: "" },
  transactions_filter: { index: 0, label: "pages.wallet.txhistory.all", value: (c) => true },
  transaction_id_filter: { index: 7, label: "Transaction", value: "" },
  conversion_data: {
    sats: 0,
    currentPrice: 0.0
  },
  signature_data: [],
  processing_signature_data: ["0x3e02c9705010cb004c3c83cdc38a0f59f3a4bf5d5d0a9fc316b04a998c03f9a86e63f8bed9d441a0efd0a1ac9ac97891fe35a4f211fff9729c094dcf3d279c411c"]
}
