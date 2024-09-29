export const isReady = (state) => {
  const { daemons, app } = state.app.config
  const config_daemon = daemons[app.net_type]

  let target_height
  if (config_daemon.type === "local") {
    target_height = Math.max(state.daemon.info.height, state.daemon.info.target_height)
  } else {
    target_height = state.daemon.info.height
  }

  return state.wallet.info.height >= (target_height - 1)
}

export const ethereum_network = (state) => {
  return state.ethereum.networks[state.ethereum.ethereum_network_index]
}

export const filtered_pools = (state) => {
  if (state.pools_filter.index === 0 && !state.node_id_filter.value & !state.operator_id_filter.value) {
    return state.pools.pool_list
  }
  let partialSearch = state.pools.pool_list.filter(state.pools_filter.value)
  if (!!state.node_id_filter.value) {
    const f = (c) => c.service_node_pubkey.startsWith(state.node_id_filter.value)
    partialSearch = partialSearch.filter(f)
  }
  if (!!state.operator_id_filter.value) {
    const f = (c) => c.operator_address.startsWith(state.operator_id_filter.value)
    partialSearch = partialSearch.filter(f)
  }
  return partialSearch
}

export const staked_pools = (state, getters) => {
  return getters.filtered_pools.filter(pool => pool.is_operator)
}

export const signature_data = (state, getters) => {
  return state.signature_data
}

export const filtered_transactions = (state) => {
  if (state.transactions_filter.index === 0 && !state.transaction_id_filter.value) {
    return state.wallet.transactions.tx_list
  }
  if (!!state.transaction_id_filter.value) {
    const f = (c) => c.txid.startsWith(state.transaction_id_filter.value)
    return state.wallet.transactions.tx_list.filter(state.transactions_filter.value).filter(f)
  } else {
    return state.wallet.transactions.tx_list.filter(state.transactions_filter.value)
  }
}

export const get_transactions_filter = (state) => {
  return state.transactions_filter
}

export const get_transaction_id_filter = (state) => {
  return state.transaction_id_filter
}

export const get_pools_filter = (state) => {
  return state.pools_filter
}

export const get_node_id_filter = (state) => {
  return state.node_id_filter
}

export const get_operator_id_filter = (state) => {
  return state.operator_id_filter
}

export const daysOfTransactions = (state) => {
  return state.app.pending_config.app.daysOfTransactions
}

export const isAbleToSend = (state) => {
  const { daemons, app } = state.app.config
  const config_daemon = daemons[app.net_type]

  let target_height
  if (config_daemon.type === "local") {
    target_height = Math.max(state.daemon.info.height, state.daemon.info.target_height)
  } else {
    target_height = state.daemon.info.height
  }

  if (config_daemon.type === "local_remote") {
    return state.daemon.info.height_without_bootstrap >= target_height && state.wallet.info.height >= (target_height - 1)
  } else {
    return state.wallet.info.height >= (target_height - 1)
  }
}

export const get_address_list = (state) => {
  return state.wallet.address_list.address_book.concat(state.wallet.address_list.address_book_starred)
}
