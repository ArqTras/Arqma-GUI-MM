import state from "./state"

export const resetWalletData = (state) => {
  state.commit("reset_wallet_data", {
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
  })
  state.commit("set_sweep_all_progress", null)
}

export const resetPoolsData = (state) => {
  state.commit("set_pools_data", {
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
  })
}

export const resetWalletStatus = (state) => {
  state.commit("reset_wallet_status", {
    code: 1,
    message: null
  })
}

export const savePendingConfig = (state, value) => {
  state.commit("save_pending_config", {
    config: value
  })
}

export const setEthereumData = (state, value) => {
  state.commit("set_ethereum_data", {
    config: value
  })
}

export const notifier = (state, value) => {
  state.commit("notifier", value)
}

export const setAppData = (state, value) => {
  state.commit("set_app_data", value)
}

export const set_pools_filter = (state, data) => {
  state.commit("set_pools_filter", data)
}

export const set_transactions_filter = (state, data) => {
  state.commit("set_transactions_filter", data)
}

export const set_transaction_id_filter = (state, data) => {
  state.commit("set_transaction_id_filter", data)
}

export const set_node_id_filter = (state, data) => {
  state.commit("set_node_id_filter", data)
}

export const set_operator_id_filter = (state, data) => {
  state.commit("set_operator_id_filter", data)
}

export const set_daysOfTransactions = (state, data) => {
  state.commit("set_daysOfTransactions", data)
}

export const set_inactivityTimeout = (state, data) => {
  state.commit("set_inactivityTimeout", data)
}

export const set_processing_signature_data = (state, data) => {
  state.commit("set_processing_signature_data", data)
}
