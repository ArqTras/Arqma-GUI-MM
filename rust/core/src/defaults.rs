use crate::merge::merge_json;
use serde_json::{json, Value};

use crate::config::ArqmaPaths;

/// `Backend.defaults` (without `appearance` / `ethereum` — validation baseline only).
pub fn build_defaults (paths: &ArqmaPaths) -> Value {
  let d = |extra: Value| {
    let base = json!({
      "type": "remote",
      "p2p_bind_ip": "0.0.0.0",
      "p2p_bind_port": 19993,
      "rpc_bind_ip": "127.0.0.1",
      "rpc_bind_port": 19994,
      "zmq_rpc_bind_ip": "127.0.0.1",
      "zmq_rpc_bind_port": 19995,
      "out_peers": -1,
      "in_peers": -1,
      "limit_rate_up": -1,
      "limit_rate_down": -1,
      "log_level": 0
    });
    merge_json(&base, &extra)
  };
  let daemons = json!({
    "mainnet": d(json!({ "remote_host": "node1.arqma.com", "remote_port": 19994 })),
    "stagenet": d(json!({ "type": "local", "p2p_bind_port": 39993, "rpc_bind_port": 39994, "zmq_rpc_bind_port": 39995 })),
    "testnet": d(json!({ "type": "local", "p2p_bind_port": 29993, "rpc_bind_port": 29994, "zmq_rpc_bind_port": 29995 }))
  });
  json!({
    "daemons": daemons,
    "app": {
      "data_dir": paths.config_dir,
      "wallet_data_dir": paths.wallet_dir,
      "net_type": "mainnet",
      "scan": false,
      "promptForPassword": true,
      "daysOfTransactions": 1,
      "loggingLevel": "error",
      "inactivityTimeout": 5
    },
    "wallet": { "rpc_bind_port": 9999, "log_level": 1 }
  })
}

/// `this.ethereum` from `backend.js` (initial network list; UI may override from disk).
pub fn default_ethereum () -> Value {
  json!({
    "ethereum_network_index": "0",
    "networks": [
      [
        {
          "token_name": "ETH",
          "network": "ethereum",
          "id": 1,
          "token_address": "0x0d40aD54EDc0A3632A1996e5f8fd10b91f298A27",
          "bridge_address": "0x631a2C078aE1dF2d04062DEca539197Ef5AC546e",
          "explorer": "https://etherscan.io/tx/",
          "governance": "Tw1WW1jYkS3144DkXTDQgg6j2fDk28KuDeYdQZb91UvnZ462yRExJz2h7k116wXbRp4JhcYyfb3PabpTuaRX9DiG2U5kGJ6wS"
        },
        {
          "token_name": "BNB",
          "network": "bnb",
          "id": 56,
          "token_address": "0x0d40aD54EDc0A3632A1996e5f8fd10b91f298A27",
          "bridge_address": "0x631a2C078aE1dF2d04062DEca539197Ef5AC546e",
          "explorer": "https://bscscan.com/tx/",
          "governance": "Tw1WW1jYkS3144DkXTDQgg6j2fDk28KuDeYdQZb91UvnZ462yRExJz2h7k116wXbRp4JhcYyfb3PabpTuaRX9DiG2U5kGJ6wS"
        }
      ]
    ]
  })
}

/// Initial `this.config_data` (defaults + appearance + ethereum), like `init`.
pub fn build_initial_config_data (paths: &ArqmaPaths) -> Value {
  let def = build_defaults(paths);
  let a = json!({ "appearance": { "theme": "dark" } });
  let eth = json!({ "ethereum": default_ethereum() });
  let m1 = merge_json(&def, &a);
  merge_json(&m1, &eth)
}
