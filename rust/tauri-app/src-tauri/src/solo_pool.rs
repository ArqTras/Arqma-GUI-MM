use crate::backend_state::WalletBackendState;
use crate::gateway_emit::emit_receive;
use crate::json_rpc_client::daemon_post;
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::net::UdpSocket;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use tauri::AppHandle;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;
use tokio::sync::mpsc;
use tokio::sync::{oneshot, Mutex};
use tokio::time::{interval, Duration, MissedTickBehavior};

fn is_persist_session (session_id: &str) -> bool {
  session_id.starts_with("persist-")
}

fn average_block_effort (blocks: &[Value]) -> f64 {
  let mut sum = 0f64;
  let mut n = 0u32;
  for b in blocks {
    let diff = b.get("diff").and_then(|v| v.as_f64()).unwrap_or(0.);
    let hashes = b.get("hashes").and_then(|v| v.as_f64()).unwrap_or(0.);
    if diff > 0. {
      sum += hashes / diff;
      n += 1;
    }
  }
  if n == 0 {
    0.
  } else {
    ((sum / n as f64) * 100.).round() / 100.
  }
}

#[derive(Clone, Default)]
struct JobState {
  id: String,
  blob: String,
  target: String,
  height: u64,
  difficulty: u64,
  seed_hash: String,
  next_seed_hash: String,
  created_ms: i64
}

#[derive(Clone, Default)]
struct WorkerState {
  session_id: String,
  miner: String,
  last_share_ms: i64,
  last_activity_ms: i64,
  last_retarget_ms: i64,
  difficulty: u64,
  last_job_id: String,
  shares: u64,
  rejects: u64,
  hashes_total: u64,
  share_times_ms: Vec<i64>,
  share_events: Vec<(i64, u64)>,
  hashrate_5min: u64,
  hashrate_1hr: u64,
  hashrate_6hr: u64,
  hashrate_24hr: u64
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct PersistWorker {
  miner: String,
  last_share_ms: i64,
  difficulty: u64,
  shares: u64,
  rejects: u64,
  hashes_total: u64,
  share_times_ms: Vec<i64>,
  share_events: Vec<(i64, u64)>
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct PersistData {
  workers: Vec<PersistWorker>,
  blocks: Vec<Value>
}

fn pool_stats_path (config_dir: &str) -> PathBuf {
  Path::new(config_dir).join("gui").join("solo_pool_stats.json")
}

fn pool_stats_db_path (config_dir: &str) -> PathBuf {
  Path::new(config_dir).join("gui").join("solo_pool_stats.sqlite")
}

fn sqlite_open (config_dir: &str) -> Option<Connection> {
  let p = pool_stats_db_path(config_dir);
  if let Some(parent) = p.parent() {
    let _ = fs::create_dir_all(parent);
  }
  Connection::open(p).ok()
}

fn sqlite_ensure_schema (conn: &Connection) {
  let _ = conn.execute_batch(
    "
    CREATE TABLE IF NOT EXISTS workers (
      miner TEXT PRIMARY KEY,
      last_share_ms INTEGER NOT NULL,
      difficulty INTEGER NOT NULL,
      shares INTEGER NOT NULL,
      rejects INTEGER NOT NULL,
      hashes_total INTEGER NOT NULL,
      share_times_json TEXT NOT NULL DEFAULT '[]'
    );
    CREATE TABLE IF NOT EXISTS blocks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      status INTEGER NOT NULL,
      hash TEXT NOT NULL DEFAULT '',
      height INTEGER NOT NULL DEFAULT 0,
      time_found INTEGER NOT NULL DEFAULT 0,
      miner TEXT NOT NULL DEFAULT '',
      reward INTEGER NOT NULL DEFAULT -1,
      diff INTEGER NOT NULL DEFAULT 0,
      hashes INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE IF NOT EXISTS hashrate_samples (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      miner TEXT NOT NULL,
      ts_ms INTEGER NOT NULL,
      hashes INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_hashrate_samples_miner_ts ON hashrate_samples(miner, ts_ms);
    ",
  );
}

fn load_persisted (config_dir: &str) -> PersistData {
  let Some(conn) = sqlite_open(config_dir) else {
    return PersistData::default();
  };
  sqlite_ensure_schema(&conn);

  let mut out = PersistData::default();
  let mut worker_samples: HashMap<String, Vec<(i64, u64)>> = HashMap::new();
  if let Ok(mut stmt) = conn.prepare(
    "SELECT miner, ts_ms, hashes
     FROM hashrate_samples
     ORDER BY miner ASC, ts_ms ASC"
  ) {
    let rows = stmt.query_map([], |row| {
      Ok((
        row.get::<_, String>(0)?,
        row.get::<_, i64>(1)?,
        row.get::<_, i64>(2)?,
      ))
    });
    if let Ok(rows) = rows {
      for (miner, ts_ms, hashes_i64) in rows.flatten() {
        worker_samples
          .entry(miner)
          .or_default()
          .push((ts_ms, hashes_i64.max(0) as u64));
      }
    }
  }

  if let Ok(mut stmt) = conn.prepare(
    "SELECT miner, last_share_ms, difficulty, shares, rejects, hashes_total, share_times_json
     FROM workers
     ORDER BY miner ASC"
  ) {
    let rows = stmt.query_map([], |row| {
      let miner: String = row.get(0)?;
      let share_times_json: String = row.get(6)?;
      let share_times_ms = serde_json::from_str::<Vec<i64>>(&share_times_json).unwrap_or_default();
      Ok(PersistWorker {
        miner: miner.clone(),
        last_share_ms: row.get::<_, i64>(1)?,
        difficulty: row.get::<_, i64>(2)?.max(0) as u64,
        shares: row.get::<_, i64>(3)?.max(0) as u64,
        rejects: row.get::<_, i64>(4)?.max(0) as u64,
        hashes_total: row.get::<_, i64>(5)?.max(0) as u64,
        share_times_ms,
        share_events: worker_samples.remove(&miner).unwrap_or_default(),
      })
    });
    if let Ok(rows) = rows {
      out.workers = rows.flatten().collect();
    }
  }

  if let Ok(mut stmt) = conn.prepare(
    "SELECT status, hash, height, time_found, miner, reward, diff, hashes
     FROM blocks
     ORDER BY id DESC
     LIMIT 100"
  ) {
    let rows = stmt.query_map([], |row| {
      Ok(json!({
        "status": row.get::<_, i64>(0)?,
        "hash": row.get::<_, String>(1)?,
        "height": row.get::<_, i64>(2)?,
        "timeFound": row.get::<_, i64>(3)?,
        "miner": row.get::<_, String>(4)?,
        "reward": row.get::<_, i64>(5)?,
        "diff": row.get::<_, i64>(6)?,
        "hashes": row.get::<_, i64>(7)?
      }))
    });
    if let Ok(rows) = rows {
      let mut blocks: Vec<Value> = rows.flatten().collect();
      blocks.reverse();
      out.blocks = blocks;
    }
  }

  out
}

fn save_persisted (config_dir: &str, data: &PersistData) {
  let Some(mut conn) = sqlite_open(config_dir) else {
    return;
  };
  sqlite_ensure_schema(&conn);
  let Ok(txn) = conn.transaction() else {
    return;
  };
  let _ = txn.execute("DELETE FROM workers", []);
  let _ = txn.execute("DELETE FROM blocks", []);
  let _ = txn.execute("DELETE FROM hashrate_samples", []);

  for w in &data.workers {
    let share_times_json = serde_json::to_string(&w.share_times_ms).unwrap_or_else(|_| "[]".to_string());
    let _ = txn.execute(
      "INSERT OR REPLACE INTO workers (miner, last_share_ms, difficulty, shares, rejects, hashes_total, share_times_json)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
      params![
        w.miner,
        w.last_share_ms,
        w.difficulty as i64,
        w.shares as i64,
        w.rejects as i64,
        w.hashes_total as i64,
        share_times_json
      ],
    );
    for (ts_ms, hashes) in &w.share_events {
      let _ = txn.execute(
        "INSERT INTO hashrate_samples (miner, ts_ms, hashes) VALUES (?1, ?2, ?3)",
        params![w.miner, *ts_ms, *hashes as i64],
      );
    }
  }

  for b in &data.blocks {
    let _ = txn.execute(
      "INSERT INTO blocks (status, hash, height, time_found, miner, reward, diff, hashes)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
      params![
        b.get("status").and_then(|v| v.as_i64()).unwrap_or(0),
        b.get("hash").and_then(|v| v.as_str()).unwrap_or(""),
        b.get("height").and_then(|v| v.as_i64()).unwrap_or(0),
        b.get("timeFound").and_then(|v| v.as_i64()).unwrap_or(0),
        b.get("miner").and_then(|v| v.as_str()).unwrap_or(""),
        b.get("reward").and_then(|v| v.as_i64()).unwrap_or(-1),
        b.get("diff").and_then(|v| v.as_i64()).unwrap_or(0),
        b.get("hashes").and_then(|v| v.as_i64()).unwrap_or(0),
      ],
    );
  }
  let _ = txn.commit();
}

fn migrate_json_to_sqlite (config_dir: &str) {
  let Some(conn) = sqlite_open(config_dir) else {
    return;
  };
  sqlite_ensure_schema(&conn);
  let has_any = conn
    .query_row("SELECT EXISTS(SELECT 1 FROM workers LIMIT 1)", [], |r| r.get::<_, i64>(0))
    .unwrap_or(0)
    == 1
    || conn
      .query_row("SELECT EXISTS(SELECT 1 FROM blocks LIMIT 1)", [], |r| r.get::<_, i64>(0))
      .unwrap_or(0)
      == 1
    || conn
      .query_row("SELECT EXISTS(SELECT 1 FROM hashrate_samples LIMIT 1)", [], |r| r.get::<_, i64>(0))
      .unwrap_or(0)
      == 1;
  if has_any {
    return;
  }

  let json_path = pool_stats_path(config_dir);
  let Ok(raw) = fs::read_to_string(&json_path) else {
    return;
  };
  let Ok(data) = serde_json::from_str::<PersistData>(&raw) else {
    return;
  };
  save_persisted(config_dir, &data);
  let migrated_path = json_path.with_extension("json.migrated");
  let _ = fs::rename(&json_path, &migrated_path);
}


fn is_hex_8 (s: &str) -> bool {
  s.len() == 8 && s.bytes().all(|b| b.is_ascii_hexdigit())
}

fn is_hex_64 (s: &str) -> bool {
  s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit())
}

/// XMRig `Client::parseJob` code **4** is `!job.setBlob` — not auth / diff.
/// Rejecting invalid daemon blobs avoids sending a login `job` that XMRig drops with "login error code: 4"
/// and then reconnect loops ("no active pools").
fn blocktemplate_blob_ok (blob: &str) -> bool {
  let n = blob.len();
  // Keep lower bound strict: very short blobs can pass hex checks but still fail
  // XMRig parseJob/setBlob (login error code 4, then "no active pools").
  // 76 bytes (152 hex chars) covers block header + nonce area for RandomX templates.
  if n < 152 || n > 2 * 1024 * 1024 {
    return false;
  }
  if n % 2 != 0 {
    return false;
  }
  blob.bytes().all(|b| b.is_ascii_hexdigit())
}

/// Approximate compact stratum target (4-byte LE hex) from difficulty.
/// Electron uses full 256-bit math; here we keep a deterministic monotonic approximation.
fn difficulty_to_target_hex (difficulty: u64) -> String {
  let d = difficulty.max(1);
  // Stratum compact target is 32-bit; using u64::MAX here collapses most
  // practical difficulties to 0xffffffff (effective diff ~1).
  let t = ((u32::MAX as u64) / d).max(1) as u32;
  let le = t.to_le_bytes();
  hex::encode(le)
}

fn passes_compact_target (result_hash: &str, compact_target_le_hex: &str) -> bool {
  if !is_hex_64(result_hash) || !is_hex_8(compact_target_le_hex) {
    return false;
  }
  let target_le = u32::from_le_bytes({
    let mut a = [0u8; 4];
    if let Ok(v) = hex::decode(compact_target_le_hex) {
      if v.len() == 4 {
        a.copy_from_slice(&v);
      }
    }
    a
  });
  let Ok(hash_bytes) = hex::decode(result_hash) else {
    return false;
  };
  if hash_bytes.len() != 32 {
    return false;
  }
  // Different miners/pool stacks disagree on which 32-bit slice/endian should
  // be used for compact target checks. Accept any canonical variant to avoid
  // false "low difficulty share" rejects caused purely by byte-order mismatch.
  let first = [hash_bytes[0], hash_bytes[1], hash_bytes[2], hash_bytes[3]];
  let last = [hash_bytes[28], hash_bytes[29], hash_bytes[30], hash_bytes[31]];
  let samples = [
    u32::from_le_bytes(first),
    u32::from_be_bytes(first),
    u32::from_le_bytes(last),
    u32::from_be_bytes(last),
  ];
  samples.into_iter().any(|sample| sample <= target_le)
}

fn pool_enabled (st: &WalletBackendState) -> bool {
  st
    .config_data
    .get("pool")
    .and_then(|p| p.get("server"))
    .and_then(|s| s.get("enabled"))
    .and_then(|v| v.as_bool())
    .unwrap_or(false)
}

pub fn preferred_bind_ip () -> String {
  let Ok(sock) = UdpSocket::bind("0.0.0.0:0") else {
    return "127.0.0.1".to_string();
  };
  let _ = sock.connect("8.8.8.8:80");
  sock
    .local_addr()
    .map(|a| a.ip().to_string())
    .unwrap_or_else(|_| "127.0.0.1".to_string())
}

fn pool_mining_address (st: &WalletBackendState) -> String {
  st
    .config_data
    .get("pool")
    .and_then(|p| p.get("mining"))
    .and_then(|m| m.get("address"))
    .and_then(|v| v.as_str())
    .unwrap_or("")
    .to_string()
}

fn pool_bind_addr (st: &WalletBackendState) -> Option<String> {
  let raw_ip = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("server"))
    .and_then(|s| s.get("bindIP"))
    .and_then(|v| v.as_str())
    .unwrap_or("");
  let ip = if raw_ip.is_empty() || raw_ip == "0.0.0.0" || raw_ip == "127.0.0.1" {
    preferred_bind_ip()
  } else {
    raw_ip.to_string()
  };
  let port = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("server"))
    .and_then(|s| s.get("bindPort"))
    .and_then(|v| v.as_u64())
    .unwrap_or(3333);
  Some(format!("{ip}:{port}"))
}

fn daemon_host_port (st: &WalletBackendState) -> Option<(String, u16)> {
  let net = st
    .config_data
    .get("app")
    .and_then(|a| a.get("net_type"))
    .and_then(|v| v.as_str())
    .unwrap_or("mainnet");
  let cfg = st.config_data.get("daemons")?.get(net)?;
  let typ = cfg.get("type").and_then(|v| v.as_str()).unwrap_or("remote");
  if typ == "remote" {
    let host = cfg.get("remote_host").and_then(|v| v.as_str())?.to_string();
    let port = cfg.get("remote_port").and_then(|v| v.as_u64())? as u16;
    Some((host, port))
  } else {
    let host = cfg
      .get("rpc_bind_ip")
      .and_then(|v| v.as_str())
      .unwrap_or("127.0.0.1")
      .to_string();
    let port = cfg.get("rpc_bind_port").and_then(|v| v.as_u64()).unwrap_or(19994) as u16;
    Some((host, port))
  }
}

fn now_ms () -> i64 {
  std::time::SystemTime::now()
    .duration_since(std::time::UNIX_EPOCH)
    .map(|d| d.as_millis() as i64)
    .unwrap_or(0)
}

fn sanitize_worker_name (raw: &str) -> String {
  let mut out = String::new();
  for ch in raw.chars() {
    if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
      out.push(ch);
    } else if ch.is_ascii_whitespace() {
      out.push('-');
    }
  }
  if out.is_empty() {
    "Unnamed_Worker".to_string()
  } else {
    out
  }
}

fn worker_job_id (base_job_id: &str, difficulty: u64) -> String {
  format!("{base_job_id}|{difficulty}")
}

fn canonical_job_id (job_id: &str) -> &str {
  job_id.split('|').next().unwrap_or(job_id)
}

fn calc_hashrate (hashes: u64, ms: i64) -> u64 {
  if hashes == 0 || ms <= 0 {
    return 0;
  }
  ((hashes as f64) / ((ms as f64) / 1000.0)) as u64
}

fn prune_share_events (ws: &mut WorkerState, now: i64) {
  ws.share_events.retain(|(ts, _)| now.saturating_sub(*ts) <= 24 * 60 * 60 * 1000);
}

fn window_hashrate (ws: &WorkerState, now: i64, window_ms: i64) -> u64 {
  if window_ms <= 0 {
    return 0;
  }
  let hashes: u64 = ws
    .share_events
    .iter()
    .filter(|(ts, _)| now.saturating_sub(*ts) <= window_ms)
    .map(|(_, h)| *h)
    .sum();
  calc_hashrate(hashes, window_ms)
}

fn build_hashrate_graph (ws: &WorkerState, now: i64, bucket_ms: i64, buckets: i64) -> Value {
  let mut out = serde_json::Map::new();
  for i in 0..buckets {
    let bucket_end = now - (i * bucket_ms);
    let bucket_start = bucket_end - bucket_ms;
    let hashes: u64 = ws
      .share_events
      .iter()
      .filter(|(ts, _)| *ts > bucket_start && *ts <= bucket_end)
      .map(|(_, h)| *h)
      .sum();
    let rate = calc_hashrate(hashes, bucket_ms);
    out.insert(bucket_start.to_string(), json!(rate));
  }
  Value::Object(out)
}

fn maybe_retarget (
  ws: &mut WorkerState,
  now: i64,
  var_enabled: bool,
  retarget_time_s: u64,
  target_time_s: u64,
  variance_percent: u64,
  min_diff: u64,
  max_diff: u64,
  max_jump_percent: u64,
) -> bool {
  if !var_enabled || ws.share_times_ms.len() < 4 {
    return false;
  }
  let retarget_ms = (retarget_time_s as i64).saturating_mul(1000);
  if retarget_ms > 0 && now.saturating_sub(ws.last_retarget_ms) < retarget_ms {
    return false;
  }
  let avg_ms = ws.share_times_ms.iter().copied().sum::<i64>() / (ws.share_times_ms.len() as i64);
  if avg_ms <= 0 {
    return false;
  }
  let target_ms = (target_time_s as i64) * 1000;
  let variance_ms = (target_ms * variance_percent as i64) / 100;
  let min_target = target_ms - variance_ms;
  let max_target = target_ms + variance_ms;
  if avg_ms >= min_target && avg_ms <= max_target {
    return false;
  }
  let prev = ws.difficulty;
  let raw = ((ws.difficulty as f64) * (target_ms as f64) / (avg_ms as f64)) as u64;
  let jump = max_jump_percent.max(1);
  let min_step = ws.difficulty.saturating_mul(100 - jump).saturating_div(100);
  let max_step = ws.difficulty.saturating_mul(100 + jump).saturating_div(100);
  ws.difficulty = raw.clamp(min_step.max(min_diff), max_step.min(max_diff).max(min_diff));
  let changed = ws.difficulty != prev;
  if changed {
    ws.last_retarget_ms = now;
  }
  changed
}

async fn refresh_job (
  http: &reqwest::Client,
  daemon: &(String, u16),
  wallet_address: &str,
  job: &Arc<Mutex<JobState>>,
  job_ring: &Arc<Mutex<Vec<JobState>>>,
  seq: &AtomicU64,
) {
  if wallet_address.is_empty() {
    return;
  }
  let params = json!({
    "wallet_address": wallet_address,
    "reserve_size": 1
  });
  let Ok(v) = daemon_post(http, &daemon.0, daemon.1, "get_block_template", 0, &params).await else {
    return;
  };
  if v.get("error").is_some() {
    return;
  }
  let Some(r) = v.get("result") else {
    return;
  };
  let blob = r.get("blocktemplate_blob").and_then(|x| x.as_str()).unwrap_or("").to_string();
  if !blocktemplate_blob_ok(&blob) {
    return;
  }
  let height = r.get("height").and_then(|x| x.as_u64()).unwrap_or(0);
  let difficulty = r.get("difficulty").and_then(|x| x.as_u64()).unwrap_or(0);
  let seed_hash = r.get("seed_hash").and_then(|x| x.as_str()).unwrap_or("").to_string();
  let next_seed_hash = r.get("next_seed_hash").and_then(|x| x.as_str()).unwrap_or("").to_string();
  let id = format!("{:x}", seq.fetch_add(1, Ordering::SeqCst));
  let mut j = job.lock().await;
  j.id = id;
  j.blob = blob;
  j.target = difficulty_to_target_hex(difficulty);
  j.height = height;
  j.difficulty = difficulty;
  j.seed_hash = seed_hash;
  j.next_seed_hash = next_seed_hash;
  j.created_ms = now_ms();
  let mut ring = job_ring.lock().await;
  ring.push(j.clone());
  if ring.len() > 8 {
    let keep_from = ring.len().saturating_sub(8);
    ring.drain(0..keep_from);
  }
}

async fn send_line (writer: &mut tokio::net::tcp::OwnedWriteHalf, payload: &Value) -> Result<(), String> {
  let s = format!("{payload}\n");
  writer.write_all(s.as_bytes()).await.map_err(|e| e.to_string())
}

pub fn start (app: &AppHandle, st: &mut WalletBackendState) {
  stop(st);
  if !pool_enabled(st) {
    return;
  }
  let mining_address = pool_mining_address(st);
  if mining_address.is_empty() {
    let _ = emit_receive(
      app,
      "set_pool_data",
      json!({ "status": -1 }),
    );
    return;
  }
  let Some(addr) = pool_bind_addr(st) else {
    return;
  };
  let Some(daemon) = daemon_host_port(st) else {
    return;
  };
  let fixed_diff_separator = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("varDiff"))
    .and_then(|v| v.get("fixedDiffSeparator"))
    .and_then(|v| v.as_str())
    .unwrap_or(".")
    .to_string();
  let config_dir = st.paths.config_dir.clone();
  migrate_json_to_sqlite(&config_dir);
  let persisted = load_persisted(&config_dir);
  let var_enabled = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("varDiff"))
    .and_then(|v| v.get("enabled"))
    .and_then(|v| v.as_bool())
    .unwrap_or(true);
  let var_start_diff = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("varDiff"))
    .and_then(|v| v.get("startDiff"))
    .and_then(|v| v.as_u64())
    .unwrap_or(5000)
    .clamp(1000, 1_000_000);
  let var_retarget_time_s = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("varDiff"))
    .and_then(|v| v.get("retargetTime"))
    .and_then(|v| v.as_u64())
    .unwrap_or(60);
  let var_target_time_s = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("varDiff"))
    .and_then(|v| v.get("targetTime"))
    .and_then(|v| v.as_u64())
    .unwrap_or(45);
  let var_variance_percent = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("varDiff"))
    .and_then(|v| v.get("variancePercent"))
    .and_then(|v| v.as_u64())
    .unwrap_or(45);
  let var_min_diff = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("varDiff"))
    .and_then(|v| v.get("minDiff"))
    .and_then(|v| v.as_u64())
    .unwrap_or(1000);
  let var_max_diff = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("varDiff"))
    .and_then(|v| v.get("maxDiff"))
    .and_then(|v| v.as_u64())
    .unwrap_or(1_000_000);
  let var_max_jump_percent = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("varDiff"))
    .and_then(|v| v.get("maxJump"))
    .and_then(|v| v.as_u64())
    .unwrap_or(30);
  let miner_timeout_ms = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("mining"))
    .and_then(|m| m.get("minerTimeout"))
    .and_then(|v| v.as_u64())
    .unwrap_or(900)
    .saturating_mul(1000)
    .max(60_000) as i64;
  let (tx, mut rx) = oneshot::channel::<()>();
  st.solo_pool_shutdown = Some(tx);
  let app = app.clone();
  let http = reqwest::Client::builder()
    .timeout(Duration::from_secs(20))
    .build()
    .unwrap_or_else(|_| reqwest::Client::new());
  st.solo_pool_task = Some(tokio::spawn(async move {
    // Windows may keep socket in a transient state right after stop/start toggle.
    // Retry binding briefly before failing with error 10048.
    let mut last_bind_err = String::new();
    let mut listener_opt = None;
    for _ in 0..20 {
      match TcpListener::bind(&addr).await {
        Ok(l) => {
          listener_opt = Some(l);
          break;
        }
        Err(e) => {
          last_bind_err = e.to_string();
          tokio::time::sleep(Duration::from_millis(150)).await;
        }
      }
    }
    let Some(listener) = listener_opt else {
      let _ = emit_receive(
        &app,
        "set_pool_data",
        json!({
          "status": -1,
          "stats": { "activeWorkers": 0 },
          "workers": []
        }),
      );
      let _ = emit_receive(
        &app,
        "show_notification",
        json!({
          "type": "negative",
          "message": format!("Solo pool bind failed: {last_bind_err}"),
          "timeout": 4000
        }),
      );
      return;
    };

    let workers: Arc<Mutex<HashMap<String, WorkerState>>> = Arc::new(Mutex::new(HashMap::new()));
    let senders: Arc<Mutex<HashMap<String, mpsc::UnboundedSender<Value>>>> = Arc::new(Mutex::new(HashMap::new()));
    let current_job: Arc<Mutex<JobState>> = Arc::new(Mutex::new(JobState::default()));
    let job_ring: Arc<Mutex<Vec<JobState>>> = Arc::new(Mutex::new(Vec::new()));
    let blocks: Arc<Mutex<Vec<Value>>> = Arc::new(Mutex::new(Vec::new()));
    {
      let mut w = workers.lock().await;
      for (idx, pw) in persisted.workers.iter().enumerate() {
        let sid = format!("persist-{idx}-{}", pw.miner);
        w.insert(sid.clone(), WorkerState {
          session_id: sid,
          miner: pw.miner.clone(),
          last_share_ms: pw.last_share_ms,
          last_activity_ms: pw.last_share_ms,
          last_retarget_ms: 0,
          difficulty: pw.difficulty.max(1000),
          last_job_id: String::new(),
          shares: pw.shares,
          rejects: pw.rejects,
          hashes_total: pw.hashes_total,
          share_times_ms: pw.share_times_ms.clone(),
          share_events: pw.share_events.clone(),
          hashrate_5min: 0,
          hashrate_1hr: 0,
          hashrate_6hr: 0,
          hashrate_24hr: 0
        });
      }
    }
    {
      let mut b = blocks.lock().await;
      *b = persisted.blocks;
    }
    let session_seq = Arc::new(AtomicU64::new(1));
    let job_seq = Arc::new(AtomicU64::new(1));
    let round_hashes = Arc::new(AtomicU64::new(0));
    // Miners that timed out: last WorkerState for the table until the same name reconnects.
    let last_disconnected: Arc<Mutex<HashMap<String, WorkerState>>> = Arc::new(Mutex::new(HashMap::new()));
    let mut prev_job_id = String::new();
    refresh_job(&http, &daemon, &mining_address, &current_job, &job_ring, job_seq.as_ref()).await;
    let mut beat = interval(Duration::from_secs(5));
    beat.set_missed_tick_behavior(MissedTickBehavior::Skip);
    let mut persist_tick = interval(Duration::from_secs(30));
    persist_tick.set_missed_tick_behavior(MissedTickBehavior::Skip);
    loop {
      tokio::select! {
        _ = &mut rx => {
          let workers_snapshot = {
            let w = workers.lock().await;
            w.values().map(|ws| PersistWorker {
              miner: ws.miner.clone(),
              last_share_ms: ws.last_share_ms,
              difficulty: ws.difficulty,
              shares: ws.shares,
              rejects: ws.rejects,
              hashes_total: ws.hashes_total,
              share_times_ms: ws.share_times_ms.clone(),
              share_events: ws.share_events.clone()
            }).collect::<Vec<_>>()
          };
          let blocks_snapshot = { blocks.lock().await.clone() };
          save_persisted(&config_dir, &PersistData { workers: workers_snapshot, blocks: blocks_snapshot });
          break;
        }
        _ = persist_tick.tick() => {
          let workers_snapshot = {
            let w = workers.lock().await;
            w.values().map(|ws| PersistWorker {
              miner: ws.miner.clone(),
              last_share_ms: ws.last_share_ms,
              difficulty: ws.difficulty,
              shares: ws.shares,
              rejects: ws.rejects,
              hashes_total: ws.hashes_total,
              share_times_ms: ws.share_times_ms.clone(),
              share_events: ws.share_events.clone()
            }).collect::<Vec<_>>()
          };
          let blocks_snapshot = { blocks.lock().await.clone() };
          save_persisted(&config_dir, &PersistData { workers: workers_snapshot, blocks: blocks_snapshot });
        }
        _ = beat.tick() => {
          refresh_job(&http, &daemon, &mining_address, &current_job, &job_ring, job_seq.as_ref()).await;
          let now = now_ms();
          let current = current_job.lock().await.clone();
          let job_changed = current.id != prev_job_id;
          prev_job_id = current.id.clone();
          let mut changed_sessions: Vec<String> = Vec::new();
          {
            let mut w = workers.lock().await;
            for ws in w.values_mut() {
              prune_share_events(ws, now);
              let old_diff = ws.difficulty;
              maybe_retarget(
                ws,
                now,
                var_enabled,
                var_retarget_time_s,
                var_target_time_s,
                var_variance_percent,
                var_min_diff,
                var_max_diff,
                var_max_jump_percent,
              );
              if job_changed || ws.difficulty != old_diff || ws.last_job_id != current.id {
                ws.last_job_id = current.id.clone();
                changed_sessions.push(ws.session_id.clone());
              }
              ws.hashrate_5min = window_hashrate(ws, now, (5 * 60 * 1000) as i64);
              ws.hashrate_1hr = window_hashrate(ws, now, (60 * 60 * 1000) as i64);
              ws.hashrate_6hr = window_hashrate(ws, now, (6 * 60 * 60 * 1000) as i64);
              ws.hashrate_24hr = window_hashrate(ws, now, (24 * 60 * 60 * 1000) as i64);
            }
          }
          {
            let to_evict: Vec<(String, WorkerState)> = {
              let w = workers.lock().await;
              w.iter()
                .filter(|(k, ws)| {
                  !is_persist_session(k)
                    && now.saturating_sub(ws.last_activity_ms) >= miner_timeout_ms
                })
                .map(|(k, ws)| (k.clone(), ws.clone()))
                .collect()
            };
            if !to_evict.is_empty() {
              let mut w = workers.lock().await;
              let mut s = senders.lock().await;
              let mut d = last_disconnected.lock().await;
              for (sid, ws) in to_evict {
                w.remove(&sid);
                s.remove(&sid);
                d.insert(ws.miner.clone(), ws);
                while d.len() > 32 {
                  if let Some(k) = d.keys().next().cloned() {
                    d.remove(&k);
                  } else {
                    break;
                  }
                }
              }
            }
          }
          if !changed_sessions.is_empty() && !current.blob.is_empty() && blocktemplate_blob_ok(&current.blob) {
            let senders_map = senders.lock().await;
            let workers_map = workers.lock().await;
            for sid in changed_sessions {
              if let (Some(tx), Some(ws)) = (senders_map.get(&sid), workers_map.get(&sid)) {
                let worker_target = difficulty_to_target_hex(ws.difficulty);
                let worker_job_id = worker_job_id(&current.id, ws.difficulty);
                let _ = tx.send(json!({
                  "jsonrpc":"2.0",
                  "method":"job",
                  "params":{
                    "blob": current.blob,
                    "job_id": worker_job_id,
                    "target": worker_target,
                    "height": current.height,
                    "algo": "rx/arq",
                    "seed_hash": current.seed_hash,
                    "next_seed_hash": current.next_seed_hash
                  }
                }));
              }
            }
          }
          let w = workers.lock().await;
          let active_count = w
            .values()
            .filter(|ws| !is_persist_session(&ws.session_id))
            .count();
          let known_miners: HashSet<String> = w.values().map(|ws| ws.miner.clone()).collect();
          let mut list: Vec<Value> = w
            .values()
            .map(|ws| {
              let graph = build_hashrate_graph(ws, now, 60_000, 60);
              json!({
                "miner": ws.miner,
                "active": !is_persist_session(&ws.session_id),
                "lastShare": ws.last_share_ms,
                "difficulty": ws.difficulty,
                "hashes": ws.hashes_total,
                "rejects": ws.rejects,
                "hashrate_5min": ws.hashrate_5min,
                "hashrate_1hr": ws.hashrate_1hr,
                "hashrate_6hr": ws.hashrate_6hr,
                "hashrate_24hr": ws.hashrate_24hr,
                "hashrate_graph": graph
              })
            })
            .collect();
          drop(w);
          {
            let d = last_disconnected.lock().await;
            for ows in d.values() {
              if known_miners.contains(&ows.miner) {
                continue;
              }
              let graph = build_hashrate_graph(ows, now, 60_000, 60);
              list.push(json!({
                "miner": ows.miner,
                "active": false,
                "lastShare": ows.last_share_ms,
                "difficulty": ows.difficulty,
                "hashes": ows.hashes_total,
                "rejects": ows.rejects,
                "hashrate_5min": ows.hashrate_5min,
                "hashrate_1hr": ows.hashrate_1hr,
                "hashrate_6hr": ows.hashrate_6hr,
                "hashrate_24hr": ows.hashrate_24hr,
                "hashrate_graph": graph
              }));
            }
          }
          let w = workers.lock().await;
          // Daemon height + network fields (one RPC); also unlock pending block rows.
          let mut network_hashrate: u64 = 0;
          let mut network_diff: u64 = 0;
          let mut network_height: u64 = 0;
          if let Ok(info) = daemon_post(&http, &daemon.0, daemon.1, "get_info", 0, &Value::Null).await {
            if let Some(r) = info.get("result") {
              if let Some(h) = r.get("height").and_then(|v| v.as_u64()) {
                network_height = h;
                let mut bl = blocks.lock().await;
                for b in bl.iter_mut() {
                  let bh = b.get("height").and_then(|v| v.as_u64()).unwrap_or(0);
                  let st = b.get("status").and_then(|v| v.as_i64()).unwrap_or(0);
                  if st == 0 && h >= bh.saturating_add(19) {
                    if let Some(o) = b.as_object_mut() {
                      o.insert("status".into(), json!(2));
                    }
                  }
                }
              }
              network_diff = r.get("difficulty").and_then(|v| v.as_u64()).unwrap_or(0);
              let target = r.get("target").and_then(|v| v.as_u64()).unwrap_or(120);
              if target > 0 {
                network_hashrate = network_diff / target;
              }
            }
          }
          let pool_h5 = w
            .values()
            .filter(|ws| !is_persist_session(&ws.session_id))
            .map(|x| x.hashrate_5min)
            .sum::<u64>();
          let rh = round_hashes.load(Ordering::Relaxed);
          let current_effort = if network_diff == 0 {
            0f64
          } else {
            ((100.0 * (rh as f64) / (network_diff as f64)).round()) / 100.0
          };
          let block_time_ms: u64 = if pool_h5 == 0 {
            0
          } else {
            1000u64.saturating_mul(120).saturating_mul(network_hashrate) / pool_h5
          };
          let blocks_snapshot = { blocks.lock().await.clone() };
          let blocks_found = blocks_snapshot.len() as u64;
          let avg_eff = average_block_effort(&blocks_snapshot);
          let _ = emit_receive(&app, "set_pool_data", json!({
            "workers": list,
            "stats": {
              "activeWorkers": active_count,
              "roundHashes": rh,
              "currentEffort": current_effort,
              "blockTime": block_time_ms,
              "blocksFound": blocks_found,
              "averageEffort": avg_eff,
              "networkHashrate": network_hashrate,
              "diff": network_diff,
              "height": network_height,
              "h": {
                "hashrate_5min": pool_h5,
                "hashrate_1hr": w.values().filter(|ws| !is_persist_session(&ws.session_id)).map(|x| x.hashrate_1hr).sum::<u64>(),
                "hashrate_6hr": w.values().filter(|ws| !is_persist_session(&ws.session_id)).map(|x| x.hashrate_6hr).sum::<u64>(),
                "hashrate_24hr": w.values().filter(|ws| !is_persist_session(&ws.session_id)).map(|x| x.hashrate_24hr).sum::<u64>()
              }
            },
            "blocks": blocks_snapshot,
            "status": 2
          }));
        }
        accepted = listener.accept() => {
          let Ok((socket, peer)) = accepted else { continue };
          let workers2 = workers.clone();
          let senders2 = senders.clone();
          let current_job2 = current_job.clone();
          let job_ring2 = job_ring.clone();
          let blocks2 = blocks.clone();
          let session_seq2 = session_seq.clone();
          let daemon2 = daemon.clone();
          let http2 = http.clone();
          let fixed_diff_separator2 = fixed_diff_separator.clone();
          let mining_addr2 = mining_address.clone();
          let job_seq2 = job_seq.clone();
          let round_hashes2 = round_hashes.clone();
          let last_disconnected2 = last_disconnected.clone();
          tokio::spawn(async move {
            let (reader_half, mut writer_half) = socket.into_split();
            let (tx_out, mut rx_out) = mpsc::unbounded_channel::<Value>();
            tokio::spawn(async move {
              while let Some(payload) = rx_out.recv().await {
                let _ = send_line(&mut writer_half, &payload).await;
              }
            });
            let mut reader = BufReader::new(reader_half);
            let mut line = String::new();
            let mut my_session_id = String::new();
            let mut seen_submits: HashMap<String, HashSet<String>> = HashMap::new();
            loop {
              line.clear();
              let n = match reader.read_line(&mut line).await {
                Ok(0) => break,
                Ok(n) => n,
                Err(_) => break
              };
              if n == 0 || line.trim().is_empty() {
                continue;
              }
              let parsed: Value = match serde_json::from_str(line.trim()) {
                Ok(v) => v,
                Err(_) => {
                  let _ = tx_out.send(json!({
                    "id": null,
                    "jsonrpc":"2.0",
                    "error":{"code":-1,"message":"Malformed stratum call"},
                    "result": null
                  }));
                  continue;
                }
              };
              let id = parsed.get("id").cloned().unwrap_or(Value::Null);
              let method = parsed.get("method").and_then(|v| v.as_str()).unwrap_or("");
              let params = parsed.get("params").cloned().unwrap_or_else(|| json!({}));

              if method == "login" {
                let login = params.get("login").and_then(|v| v.as_str()).unwrap_or("");
                let pass = params.get("pass").and_then(|v| v.as_str()).unwrap_or("");
                let rigid = params
                  .get("rigid")
                  .or_else(|| params.get("rig-id"))
                  .and_then(|v| v.as_str())
                  .unwrap_or("");
                let raw_name = if !rigid.is_empty() { rigid } else if !pass.is_empty() && pass.to_lowercase() != "x" { pass } else { login };
                let worker_name = sanitize_worker_name(raw_name);
                let mut worker_diff = 5000u64;
                if var_enabled {
                  worker_diff = var_start_diff;
                }
                let login_parts: Vec<&str> = login.split(&fixed_diff_separator2).collect();
                if login_parts.len() > 1 {
                  if let Some(last) = login_parts.last() {
                    if let Ok(d) = last.parse::<u64>() {
                      worker_diff = d.clamp(1000, 1_000_000);
                    }
                  }
                }
                let mut j = current_job2.lock().await.clone();
                if j.id.is_empty() || j.blob.is_empty() || !blocktemplate_blob_ok(&j.blob) {
                  for _ in 0u32..20 {
                    tokio::time::sleep(Duration::from_millis(150)).await;
                    refresh_job(
                      &http2,
                      &daemon2,
                      &mining_addr2,
                      &current_job2,
                      &job_ring2,
                      job_seq2.as_ref(),
                    )
                    .await;
                    j = current_job2.lock().await.clone();
                    if !j.id.is_empty() && !j.blob.is_empty() && blocktemplate_blob_ok(&j.blob) {
                      break;
                    }
                  }
                }
                if j.id.is_empty() || j.blob.is_empty() || !blocktemplate_blob_ok(&j.blob) {
                  let _ = tx_out.send(json!({
                    "id": id,
                    "jsonrpc":"2.0",
                    "error":{"code":-1,"message":"Waiting for daemon"},
                    "result": null
                  }));
                  continue;
                }
                {
                  let mut d = last_disconnected2.lock().await;
                  d.remove(&worker_name);
                }
                my_session_id = format!("{:x}", session_seq2.fetch_add(1, Ordering::SeqCst));
                let t = now_ms();
                {
                  let mut w = workers2.lock().await;
                  w.insert(my_session_id.clone(), WorkerState {
                    session_id: my_session_id.clone(),
                    miner: worker_name,
                    last_share_ms: t,
                    last_activity_ms: t,
                    last_retarget_ms: t,
                    difficulty: worker_diff,
                    last_job_id: String::new(),
                    shares: 0,
                    rejects: 0,
                    hashes_total: 0,
                    share_times_ms: Vec::new(),
                    share_events: Vec::new(),
                    hashrate_5min: 0,
                    hashrate_1hr: 0,
                    hashrate_6hr: 0,
                    hashrate_24hr: 0
                  });
                }
                {
                  let mut s = senders2.lock().await;
                  s.insert(my_session_id.clone(), tx_out.clone());
                }
                let worker_target = difficulty_to_target_hex(worker_diff);
                let worker_job_id = worker_job_id(&j.id, worker_diff);
                let _ = tx_out.send(json!({
                  "id": id,
                  "jsonrpc":"2.0",
                  "error": null,
                  "result": {
                    "id": my_session_id,
                    "job": {
                      "blob": j.blob,
                      "job_id": worker_job_id,
                      "target": worker_target,
                      "height": j.height,
                      "algo": "rx/arq",
                      "seed_hash": j.seed_hash,
                      "next_seed_hash": j.next_seed_hash
                    },
                    "extensions": ["algo", "keepalive"],
                    "keepalive": false,
                    "status":"OK"
                  }
                }));
                continue;
              }

              if method == "keepalived" || method == "keepalive" {
                if my_session_id.is_empty() {
                  let _ = tx_out.send(json!({"id": id, "jsonrpc":"2.0", "error":{"code":-1,"message":"Unauthenticated"}, "result": null}));
                  continue;
                }
                {
                  let mut w = workers2.lock().await;
                  if let Some(ws) = w.get_mut(&my_session_id) {
                    ws.last_activity_ms = now_ms();
                  }
                }
                let _ = tx_out.send(json!({"id": id, "jsonrpc":"2.0", "error": null, "result": {"status":"KEEPALIVED"}}));
                continue;
              }

              if method == "getjob" {
                if my_session_id.is_empty() {
                  let _ = tx_out.send(json!({"id": id, "jsonrpc":"2.0", "error":{"code":-1,"message":"Unauthenticated"}, "result": null}));
                  continue;
                }
                {
                  let mut w = workers2.lock().await;
                  if let Some(ws) = w.get_mut(&my_session_id) {
                    ws.last_activity_ms = now_ms();
                  }
                }
                let j = current_job2.lock().await.clone();
                if j.blob.is_empty() || !blocktemplate_blob_ok(&j.blob) {
                  let _ = tx_out.send(json!({
                    "id": id,
                    "jsonrpc":"2.0",
                    "error":{"code":-1,"message":"Waiting for daemon"},
                    "result": null
                  }));
                  continue;
                }
                let worker_target = {
                  let w = workers2.lock().await;
                  let d = w.get(&my_session_id).map(|ws| ws.difficulty).unwrap_or(5000);
                  difficulty_to_target_hex(d)
                };
                let worker_diff = {
                  let w = workers2.lock().await;
                  w.get(&my_session_id).map(|ws| ws.difficulty).unwrap_or(5000)
                };
                let worker_job_id = worker_job_id(&j.id, worker_diff);
                let _ = tx_out.send(json!({
                  "id": id,
                  "jsonrpc":"2.0",
                  "error": null,
                  "result": {
                    "blob": j.blob,
                    "job_id": worker_job_id,
                    "target": worker_target,
                    "height": j.height,
                    "algo": "rx/arq",
                    "seed_hash": j.seed_hash,
                    "next_seed_hash": j.next_seed_hash
                  }
                }));
                continue;
              }

              if method == "submit" {
                if my_session_id.is_empty() {
                  let _ = tx_out.send(json!({"id": id, "jsonrpc":"2.0", "error":{"code":-1,"message":"Unauthenticated"}, "result": null}));
                  continue;
                }
                {
                  let mut w = workers2.lock().await;
                  if let Some(ws) = w.get_mut(&my_session_id) {
                    ws.last_activity_ms = now_ms();
                  }
                }
                let job_id = params.get("job_id").and_then(|v| v.as_str()).unwrap_or("");
                let job_id_base = canonical_job_id(job_id);
                let nonce = params.get("nonce").and_then(|v| v.as_str()).unwrap_or("");
                let result_hash = params.get("result").and_then(|v| v.as_str()).unwrap_or("");
                let valid = !job_id.is_empty() && is_hex_8(nonce) && !result_hash.is_empty();
                let mut current = {
                  let ring = job_ring2.lock().await;
                  ring.iter().rev().find(|j| j.id == job_id_base).cloned()
                };
                if current.is_none() {
                  current = Some(current_job2.lock().await.clone());
                }
                let current = current.unwrap_or_default();
                let submit_key = format!("{job_id}:{nonce}");
                let set = seen_submits.entry(job_id.to_string()).or_default();
                if set.contains(&submit_key) {
                  let mut w = workers2.lock().await;
                  if let Some(ws) = w.get_mut(&my_session_id) {
                    ws.rejects = ws.rejects.saturating_add(1);
                  }
                  let _ = tx_out.send(json!({"id": id, "jsonrpc":"2.0", "error":{"code":-1,"message":"Duplicate share"}, "result": null}));
                  continue;
                }
                if !valid || current.id.is_empty() || !is_hex_64(result_hash) || job_id_base != current.id {
                  let mut w = workers2.lock().await;
                  if let Some(ws) = w.get_mut(&my_session_id) {
                    ws.rejects = ws.rejects.saturating_add(1);
                  }
                  let _ = tx_out.send(json!({"id": id, "jsonrpc":"2.0", "error":{"code":-1,"message":"Invalid work"}, "result": null}));
                  continue;
                }
                let worker_target = {
                  let w = workers2.lock().await;
                  let d = w.get(&my_session_id).map(|ws| ws.difficulty).unwrap_or(5000);
                  difficulty_to_target_hex(d)
                };
                if !passes_compact_target(result_hash, &worker_target) {
                  let mut w = workers2.lock().await;
                  if let Some(ws) = w.get_mut(&my_session_id) {
                    ws.rejects = ws.rejects.saturating_add(1);
                  }
                  let _ = tx_out.send(json!({"id": id, "jsonrpc":"2.0", "error":{"code":-1,"message":"Rejected low difficulty share"}, "result": null}));
                  continue;
                }
                set.insert(submit_key);
                {
                  let mut w = workers2.lock().await;
                  if let Some(ws) = w.get_mut(&my_session_id) {
                    let share_d = ws.difficulty;
                    let dt = now_ms().saturating_sub(ws.last_share_ms);
                    if dt > 0 {
                      ws.share_times_ms.push(dt);
                      if ws.share_times_ms.len() > 16 {
                        let keep_from = ws.share_times_ms.len().saturating_sub(16);
                        ws.share_times_ms.drain(0..keep_from);
                      }
                    }
                    ws.last_share_ms = now_ms();
                    ws.shares = ws.shares.saturating_add(1);
                    ws.hashes_total = ws.hashes_total.saturating_add(share_d);
                    ws.share_events.push((ws.last_share_ms, share_d));
                    round_hashes2.fetch_add(share_d, Ordering::Relaxed);
                    let old_diff = ws.difficulty;
                    maybe_retarget(
                      ws,
                      ws.last_share_ms,
                      var_enabled,
                      var_retarget_time_s,
                      var_target_time_s,
                      var_variance_percent,
                      var_min_diff,
                      var_max_diff,
                      var_max_jump_percent,
                    );
                    if ws.difficulty != old_diff {
                      let j = current_job2.lock().await.clone();
                      ws.last_job_id = j.id.clone();
                      let worker_target = difficulty_to_target_hex(ws.difficulty);
                      let _ = tx_out.send(json!({
                        "jsonrpc":"2.0",
                        "method":"job",
                        "params":{
                          "blob": j.blob,
                          "job_id": worker_job_id(&j.id, ws.difficulty),
                          "target": worker_target,
                          "height": j.height,
                          "algo": "rx/arq",
                          "seed_hash": j.seed_hash,
                          "next_seed_hash": j.next_seed_hash
                        }
                      }));
                    }
                  }
                }
                // Optional fast-path: if miner submits full candidate block blob, try relay to daemon.
                let maybe_blob = params.get("blob").and_then(|v| v.as_str()).unwrap_or("");
                if !maybe_blob.is_empty() {
                  if let Ok(sb) = daemon_post(&http2, &daemon2.0, daemon2.1, "submit_block", 0, &json!([maybe_blob])).await {
                    if sb.get("error").is_none() {
                      let worker_name = {
                        let w = workers2.lock().await;
                        w.get(&my_session_id).map(|ws| ws.miner.clone()).unwrap_or_else(|| "worker".to_string())
                      };
                      let total_round = round_hashes2.swap(0, Ordering::Relaxed);
                      let mut bl = blocks2.lock().await;
                      bl.push(json!({
                        "status": 0,
                        "hash": result_hash,
                        "height": current.height,
                        "timeFound": now_ms(),
                        "miner": worker_name,
                        "reward": -1,
                        "diff": current.difficulty,
                        "hashes": total_round
                      }));
                      if bl.len() > 100 {
                        let keep_from = bl.len().saturating_sub(100);
                        bl.drain(0..keep_from);
                      }
                    }
                  }
                }
                let _ = tx_out.send(json!({"id": id, "jsonrpc":"2.0", "error": null, "result": {"status":"OK"}}));
                continue;
              }

              let _ = tx_out.send(json!({
                "id": id,
                "jsonrpc":"2.0",
                "error":{"code":-1,"message":"Invalid method"},
                "result": null
              }));
            }
            if !my_session_id.is_empty() {
              let mut w = workers2.lock().await;
              w.remove(&my_session_id);
              drop(w);
              let mut s = senders2.lock().await;
              s.remove(&my_session_id);
            } else {
              let mut w = workers2.lock().await;
              w.remove(&peer.to_string());
            }
          });
        }
      }
    }
  }));
}

pub fn stop (st: &mut WalletBackendState) {
  if let Some(tx) = st.solo_pool_shutdown.take() {
    let _ = tx.send(());
  }
  if let Some(h) = st.solo_pool_task.take() {
    h.abort();
  }
}
