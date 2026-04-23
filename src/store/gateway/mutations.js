const objectAssignDeep = require("object-assign-deep")

export const set_app_data = (state, data) => {
  state.app = objectAssignDeep.noMutate(state.app, data)
}
export const set_daemon_data = (state, data) => {
  state.daemon = objectAssignDeep.noMutate(state.daemon, data)
}
export const reset_wallet_data = (state, data) => {
  state.wallet = objectAssignDeep.noMutate(state.wallet, data)
}
export const set_wallet_error = (state, data) => {
  state.wallet = objectAssignDeep.noMutate(state.wallet, data)
}
export const set_wallet_transactions = (state, data) => {
  state.wallet.transactions = data
}
export const set_wallet_transaction = (state, data) => {
  state.wallet.transactions.tx_list = state.wallet.transactions.tx_list.map(p => p.txid === data.txid ? { ...p, note: data.note } : p)
}
export const set_wallet_address_list = (state, data) => {
  state.wallet.address_list = objectAssignDeep.noMutate(state.wallet.address_list, data)
}
export const set_wallet_address_book = (state, data) => {
  state.wallet.address_list = objectAssignDeep.noMutate(state.wallet.address_list, data)
}
export const set_wallet_info = (state, data) => {
  state.wallet.info = objectAssignDeep.noMutate(state.wallet.info, data)
}
export const set_wallet_secret = (state, data) => {
  state.wallet.secret = data
}
export const reset_wallet_status = (state, data) => {
  state.wallet.status = data
}
export const set_pools_data = (state, data) => {
  state.pools = data
}
export const set_coin_price = (state, data) => {
  state.coin_price = data
}
export const set_conversion_data = (state, data) => {
  state.conversion_data = data
}
export const set_wallet_list = (state, data) => {
  state.wallets = data
}
export const set_old_gui_import_status = (state, data) => {
  state.old_gui_import_status = data
}
export const set_tx_status = (state, data) => {
  state.tx_status = data
}
export const set_sweep_all_progress = (state, data) => {
  state.sweep_all_progress = data
}
export const set_snode_status = (state, data) => {
  state.service_node_status = data
}
export const set_snode_status_unlock = (state, data) => {
  state.service_node_status.unlock = objectAssignDeep.noMutate(state.service_node_status.unlock, data)
}
export const save_pending_config = (state, data) => {
  state.app = objectAssignDeep.noMutate(state.app, data)
}
export const set_ethereum_data = (state, data) => {
  state.ethereum = objectAssignDeep.noMutate(state.ethereum, data)
}
export const notifier = (state, data) => {
  state.notifier = data
}
export const daemon_version = (state, data) => {
  state.daemon_version = data.version
}
export const set_pools_filter = (state, data) => {
  state.pools_filter = data
}
export const set_node_id_filter = (state, data) => {
  state.node_id_filter = data
}
export const set_operator_id_filter = (state, data) => {
  state.operator_id_filter = data
}
export const set_transactions_filter = (state, data) => {
  state.transactions_filter = data
}
export const set_transaction_id_filter = (state, data) => {
  state.transaction_id_filter = data
}
export const set_daysOfTransactions = (state, data) => {
  state.app.daysOfTransactions = data
}
export const set_inactivityTimeout = (state, data) => {
  state.app.inactivityTimeout = data
}
export const set_processing_signature_data = (state, data) => {
  if (!state.processing_signature_data.includes(data)) {
    state.processing_signature_data.push(data)
  }
  calculate_signature_data(state, state.signature_data)
}
export const set_signature_data = (state, data) => {
  if (state.processing_signature_data.length > 0) {
    calculate_signature_data(state, data)
  } else {
    state.signature_data = data
  }
}

const calculate_signature_data = (state, data) => {
  const dataSignatures = new Set(data.map(item => item.signature))
  state.signature_data = data.filter(item => {
    if (state.processing_signature_data.includes(item.signature)) {
      return false
    } else {
      state.processing_signature_data = state.processing_signature_data.filter(sig => dataSignatures.has(sig))
      return true
    }
  })
}
