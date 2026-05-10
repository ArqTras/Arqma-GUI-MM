//! Relay / cancel / prices / stake acquisition (from `wallet-rpc.js`).
use crate::backend_state::{WalletBackendState, WalletTxMetadata};
use crate::gateway_emit::BackendReceiveSink;
use crate::json_rpc_client::WalletRpcClient;
use tauri::AppHandle;
use reqwest::Client;
use serde_json::{json, Value};

pub const COIN_UNITS: f64 = 1_000_000_000.0;

fn parse_decimal_after_marker (text: &str, marker: &str) -> Option<f64> {
  let idx = text.find(marker)?;
  let tail = &text[idx + marker.len()..];
  let mut started = false;
  let mut number = String::new();

  for ch in tail.chars() {
    if ch.is_ascii_digit() || (ch == '.' && started) {
      started = true;
      number.push(ch);
      continue;
    }
    if started {
      break;
    }
  }

  if number.is_empty() {
    None
  } else {
    number.parse::<f64>().ok().filter(|v| v.is_finite() && *v > 0.0)
  }
}

fn rpc_err_text (e: &Value) -> String {
  e
    .get("message")
    .and_then(|m| m.as_str())
    .map(|m| {
      let m = m.to_string();
      let c = m.chars().next().map(|c| c.to_uppercase().collect::<String>()).unwrap_or_default();
      format!("{c}{}", m.chars().skip(1).collect::<String>())
    })
    .unwrap_or_else(|| "RPC error".to_string())
}

/// Remove `tx_metadata_list` entries matching `type` (Node: `cancelTransaction`).
pub fn cancel_transaction (st: &mut WalletBackendState, p: &Value) {
  let t = p
    .get("type")
    .and_then(|x| x.as_str())
    .unwrap_or("");
  st.tx_metadata_list
    .retain(|m| m.kind != t);
}

pub async fn relay_sweep_all (
  app: &AppHandle,
  st: &mut WalletBackendState,
  w: &WalletRpcClient,
  p: &Value,
) {
  let origin = p
    .get("origin")
    .map(|o| o.clone())
    .unwrap_or(Value::Null);
  let mut err = String::new();
  let items: Vec<WalletTxMetadata> = st
    .tx_metadata_list
    .iter()
    .filter(|m| m.kind == "sweepAll")
    .cloned()
    .collect();
  for t in &items {
    let r = w
      .call(
        "relay_tx",
        &json!({ "hex": t.tx_metadata }),
      )
      .await;
    match r {
      Ok(v) if v.get("error").is_none() => {}
      Ok(v) => {
        if let Some(e) = v.get("error") {
          err = rpc_err_text(e);
        }
        break;
      }
      Err(e) => {
        err = e;
        break;
      }
    }
  }
  if !err.is_empty() {
    let _ = BackendReceiveSink::emit_receive(
      app,
      "set_tx_status",
      json!({
        "code": -100,
        "message": err,
        "sending": false,
        "origin": origin
      }),
    );
  } else {
    let _ = BackendReceiveSink::emit_receive(
      app,
      "set_tx_status",
      json!({
        "code": 200,
        "message": "SweepAll transaction successfully sent",
        "sending": false,
        "origin": origin
      }),
    );
  }
  st
    .tx_metadata_list
    .retain(|m| m.kind != "sweepAll");
}

pub async fn relay_transfer (
  app: &AppHandle,
  st: &mut WalletBackendState,
  w: &WalletRpcClient,
) {
  let mut err = String::new();
  let items: Vec<WalletTxMetadata> = st
    .tx_metadata_list
    .iter()
    .filter(|m| m.kind == "transfer_split")
    .cloned()
    .collect();
  for t in &items {
    let r = w
      .call("relay_tx", &json!({ "hex": t.tx_metadata }))
      .await;
    match r {
      Ok(v) if v.get("error").is_none() => {
        if let Some(h) = v.pointer("/result/tx_hash").and_then(|h| h.as_str()) {
          if !t.note.is_empty() {
            let _ = w
              .call(
                "set_tx_notes",
                &json!({ "txids": [h], "notes": [t.note.clone()] }),
              )
              .await;
          }
        }
      }
      Ok(v) => {
        if let Some(e) = v.get("error") {
          err = rpc_err_text(e);
        }
        break;
      }
      Err(e) => {
        err = e;
        break;
      }
    }
  }
  if !err.is_empty() {
    let _ = BackendReceiveSink::emit_receive(
      app,
      "set_tx_status",
      json!({ "code": -200, "message": err, "sending": false }),
    );
  } else {
    let _ = BackendReceiveSink::emit_receive(
      app,
      "set_tx_status",
      json!({
        "code": 201,
        "message": "Transaction successfully sent",
        "sending": false
      }),
    );
  }
  st
    .tx_metadata_list
    .retain(|m| m.kind != "transfer_split");
}

pub async fn relay_stake (
  app: &AppHandle,
  st: &mut WalletBackendState,
  w: &WalletRpcClient,
  p: &Value,
) {
  let origin = p.get("origin").map(|o| o.clone()).unwrap_or(Value::Null);
  let items: Vec<WalletTxMetadata> = st
    .tx_metadata_list
    .iter()
    .filter(|m| m.kind == "stake")
    .cloned()
    .collect();
  for t in &items {
    let r = w
      .call("relay_tx", &json!({ "hex": t.tx_metadata }))
      .await;
    match r {
      Ok(v) if v.get("error").is_none() => {
        if let (Some(amt), Some(snk)) = (t.amount, t.service_node_key.as_deref()) {
          let a = amt as f64 / COIN_UNITS;
          let _ = BackendReceiveSink::emit_receive(
            app,
            "show_notification",
            json!({
              "type": "positive",
              "message": format!("Staked {a:.5} ARQ to: {snk}"),
              "timeout": 3000,
              "origin": origin
            }),
          );
        }
        if let Some(txh) = v.pointer("/result/tx_hash").and_then(|h| h.as_str()) {
          if let Some(snk) = t.service_node_key.as_deref() {
            let n = format!("Service Node: {snk}");
            let _ = w
              .call("set_tx_notes", &json!({ "txids": [txh], "notes": [n] }))
              .await;
          }
        }
      }
      Ok(v) => {
        let err = v
          .get("error")
          .map(|e| rpc_err_text(e))
          .unwrap_or_else(|| "Unknown error".to_string());
        let _ = BackendReceiveSink::emit_receive(
          app,
          "set_tx_status",
          json!({ "code": -300, "message": &err, "sending": false, "origin": origin }),
        );
        st.tx_metadata_list.retain(|m| m.kind != "stake");
        return;
      }
      Err(e) => {
        let _ = BackendReceiveSink::emit_receive(
          app,
          "set_tx_status",
          json!({ "code": -300, "message": e, "sending": false, "origin": origin }),
        );
        st.tx_metadata_list.retain(|m| m.kind != "stake");
        return;
      }
    }
  }
  st.tx_metadata_list.retain(|m| m.kind != "stake");
}

pub async fn get_coin_and_conversion (app: &AppHandle, http: &Client) {
  let mut coin: f64 = 0.0;
  // Primary ARQ/USD source: Coinpaprika (ARQ ticker id: arq-arqma).
  if let Ok(r) = http
    .get("https://api.coinpaprika.com/v1/tickers/arq-arqma")
    .send()
    .await
  {
    if let Ok(v) = r.json::<Value>().await {
      if let Some(p) = v.pointer("/quotes/USD/price").and_then(|x| x.as_f64()) {
        coin = p;
      }
    }
  }
  // Fallback for USD spot price when Coinpaprika is unavailable.
  // NonKYC market page publishes ARQ/USDT last price.
  if coin <= 0.0 {
    if let Ok(r) = http.get("https://nonkyc.io/market/ARQ_USDT").send().await {
      if let Ok(html) = r.text().await {
        if let Some(p) = parse_decimal_after_marker(&html, "ARQ/USDT") {
          coin = p;
        }
      }
    }
  }
  let _ = BackendReceiveSink::emit_receive(app, "set_coin_price", json!(coin));
  let mut sats = 0.0f64;
  let mut usd_15m = 0.0f64;
  if let Ok(r) = http
    .get("https://tradeogre.com/api/v1/ticker/BTC-ARQ")
    .send()
    .await
  {
    if let Ok(v) = r.json::<Value>().await {
      if let Some(pr) = v.get("price").and_then(|x| x.as_str()) {
        sats = pr.parse().unwrap_or(0.0);
      }
    }
  }
  if let Ok(r) = http.get("https://blockchain.info/ticker").send().await {
    if let Ok(v) = r.json::<Value>().await {
      if let Some(u) = v.pointer("/USD/15m").and_then(|x| x.as_f64()) {
        usd_15m = u;
      }
    }
  }
  let _ = BackendReceiveSink::emit_receive(
    app,
    "set_conversion_data",
    json!({ "sats": sats, "currentPrice": usd_15m }),
  );
}

/// After successful `open_wallet` / `sweepAll` etc. — extract `tx_metadata` from the RPC response.
pub fn push_sweep_metadata (st: &mut WalletBackendState, p: &Value, r: &Value) {
  let do_not = p
    .get("do_not_relay")
    .and_then(|v| v.as_bool())
    .unwrap_or(false);
  if !do_not {
    return;
  }
  let Some(res) = r.get("result") else { return };
  let Some(list) = res.get("tx_metadata_list").and_then(|l| l.as_array()) else {
    return;
  };
  for item in list {
    let h = if let Some(s) = item.as_str() {
      s.to_string()
    } else {
      item.to_string()
    };
    if h.is_empty() {
      continue;
    }
    let txh = res
      .get("tx_hash_list")
      .and_then(|l| l.as_array())
      .and_then(|a| a.get(0))
      .and_then(|x| x.as_str())
      .map(String::from);
    st
      .tx_metadata_list
      .push(WalletTxMetadata {
        tx_metadata: h,
        tx_hash: txh,
        kind: "sweepAll".into(),
        note: String::new(),
        amount: None,
        service_node_key: None
      });
  }
}

pub fn push_transfer_metadata (st: &mut WalletBackendState, p: &Value, r: &Value) {
  st
    .tx_metadata_list
    .retain(|m| m.kind != "transfer_split");
  let Some(res) = r.get("result") else { return };
  let Some(list) = res.get("tx_metadata_list").and_then(|l| l.as_array()) else {
    return;
  };
  let note = p
    .get("note")
    .and_then(|n| n.as_str())
    .unwrap_or("")
    .to_string();
  for item in list {
    let hex = if let Some(s) = item.as_str() {
      s.to_string()
    } else if let Some(s) = item.get("as_hex").and_then(|a| a.as_str()) {
      s.to_string()
    } else {
      item.to_string()
    };
    st.tx_metadata_list.push(WalletTxMetadata {
      tx_metadata: hex,
      tx_hash: None,
      kind: "transfer_split".into(),
      note: note.clone(),
      amount: None,
      service_node_key: None
    });
  }
}

pub fn push_stake_metadata (st: &mut WalletBackendState, p: &Value, r: &Value) {
  st.tx_metadata_list.retain(|m| m.kind != "stake");
  let Some(res) = r.get("result") else { return };
  let Some(h) = res.get("tx_metadata") else { return };
  let hex = h.as_str().map(str::to_string).unwrap_or_else(|| h.to_string());
  let amount_f = p.get("amount").and_then(|a| a.as_f64()).unwrap_or(0.0);
  let amount = (amount_f * COIN_UNITS) as u64;
  let sk = p
    .get("key")
    .or_else(|| p.get("service_node_key"))
    .and_then(|k| k.as_str())
    .map(String::from);
  st.tx_metadata_list.push(WalletTxMetadata {
    tx_metadata: hex,
    tx_hash: None,
    kind: "stake".into(),
    note: String::new(),
    amount: Some(amount),
    service_node_key: sk
  });
}
