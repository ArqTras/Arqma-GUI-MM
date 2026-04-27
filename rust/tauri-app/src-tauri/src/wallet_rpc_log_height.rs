//! Electron (`wallet-rpc.js`): reads **stdout** from `arqma-wallet-rpc`, matches `height_regexes`
//! (`Processed block`, skipped heights, `Blockchain sync progress`), then
//! `sendGateway("set_wallet_info", { height })` with a **2 s** minimum gap (`last_height_send_time`).
//! Electron often omits `name` on that path; we include `name` + `scan_poll_ts` for Vuex merge.
//!
//! Tauri spawns the child with stdout/stderr discarded and uses `--log-file` (same as Electron’s
//! `--log-file`); we tail that file. Log is truncated on wallet-rpc start (`wallet_process`), like
//! Electron’s `truncate(log_file, 0)` on startup.

use crate::gateway_emit::emit_receive;
use crate::AppData;
use regex::Regex;
use serde_json::json;
use std::io::{Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tauri::AppHandle;
use tauri::Manager;

fn re_processed () -> &'static Regex {
  static R: OnceLock<Regex> = OnceLock::new();
  R.get_or_init(|| {
    Regex::new(r"Processed block: <[a-f0-9]+>, height (\d+)").expect("regex Processed block")
  })
}
fn re_skipped_height () -> &'static Regex {
  static R: OnceLock<Regex> = OnceLock::new();
  R.get_or_init(|| Regex::new(r"Skipped block by height: (\d+)").expect("regex Skipped height"))
}
fn re_skipped_ts () -> &'static Regex {
  static R: OnceLock<Regex> = OnceLock::new();
  R.get_or_init(|| {
    Regex::new(r"Skipped block by timestamp, height: (\d+)").expect("regex Skipped ts")
  })
}
fn re_sync_progress () -> &'static Regex {
  static R: OnceLock<Regex> = OnceLock::new();
  R.get_or_init(|| {
    Regex::new(r"Blockchain sync progress: <[a-f0-9]+>, height (\d+)").expect("regex sync progress")
  })
}

fn max_height_in_line (line: &str) -> Option<u64> {
  let mut m: Option<u64> = None;
  for re in [
    re_processed(),
    re_skipped_height(),
    re_skipped_ts(),
    re_sync_progress(),
  ] {
    if let Some(c) = re.captures(line) {
      if let Some(n) = c.get(1).and_then(|g| g.as_str().parse::<u64>().ok()) {
        m = Some(m.map_or(n, |x| x.max(n)));
      }
    }
  }
  m
}

fn max_height_in_text (text: &str) -> Option<u64> {
  let mut m: Option<u64> = None;
  for line in text.lines() {
    if let Some(h) = max_height_in_line(line) {
      m = Some(m.map_or(h, |x| x.max(h)));
    }
  }
  m
}

/// Read up to 256 KiB appended after `from`. If the file shrank (restarted RPC), reset offset to 0.
fn read_new_bytes (path: &Path, from: u64) -> (String, u64) {
  use std::fs::File;
  let mut f = match File::open(path) {
    Ok(f) => f,
    Err(_) => return (String::new(), from),
  };
  let len = f.metadata().map(|m| m.len()).unwrap_or(0);
  let mut pos = from;
  if pos > len {
    pos = 0;
  }
  if pos < len {
    let _ = f.seek(SeekFrom::Start(pos));
  }
  let to_read = len.saturating_sub(pos).min(256 * 1024) as usize;
  let mut buf = vec![0u8; to_read];
  let n = std::io::Read::read(&mut f, &mut buf).unwrap_or(0);
  buf.truncate(n);
  let s = String::from_utf8_lossy(&buf).into_owned();
  (s, pos + n as u64)
}

/// Merge a possibly incomplete leading fragment with `chunk`; return full lines only, keep tail in `carry`.
fn take_complete_lines (carry: &mut String, chunk: &str) -> String {
  let mut s = String::new();
  std::mem::swap(carry, &mut s);
  s.push_str(chunk);
  if s.is_empty() {
    return String::new();
  }
  if s.ends_with('\n') {
    let out = s;
    return out;
  }
  if let Some(pos) = s.rfind('\n') {
    let rest = s[pos + 1..].to_string();
    let complete = s[..=pos].to_string();
    *carry = rest;
    complete
  } else {
    *carry = s;
    String::new()
  }
}

pub fn start (
  app: &AppHandle,
  st: &mut crate::backend_state::WalletBackendState,
  log_path: PathBuf,
) {
  if let Some(h) = st.wallet_log_height.take() {
    h.abort();
  }
  let name = st.wh_display_name.clone();
  if name.is_empty() {
    return;
  }
  let app = app.clone();
  st.wallet_log_height = Some(tokio::spawn(async move {
    let mut off = 0u64;
    let mut carry = String::new();
    let mut last_emit = Instant::now() - Duration::from_secs(10);
    while app.try_state::<AppData>().is_some() {
      tokio::time::sleep(Duration::from_millis(800)).await;
      let (chunk, new_off) = read_new_bytes(&log_path, off);
      off = new_off;
      if chunk.is_empty() && carry.is_empty() {
        continue;
      }
      let text = take_complete_lines(&mut carry, &chunk);
      if text.is_empty() {
        continue;
      }
      let Some(h) = max_height_in_text(&text) else {
        continue;
      };
      let merged_opt = {
        let Some(adata) = app.try_state::<AppData>() else {
          continue;
        };
        let mut b = adata.backend.lock().await;
        let prev = b.wh_stored_height;
        let m = prev.max(h);
        // Log lines can reflect an older block than `getheight` already reported — never regress
        // backend height from the tailer alone.
        if m <= prev {
          None
        } else {
          b.wh_stored_height = m;
          Some(m)
        }
      };
      let Some(merged) = merged_opt else {
        continue;
      };
      if last_emit.elapsed() < Duration::from_secs(2) {
        continue;
      }
      last_emit = Instant::now();
      let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
      let info = json!({
        "name": &name,
        "height": merged,
        "scan_poll_ts": now_ms,
      });
      let _ = emit_receive(&app, "set_wallet_info", info);
      let _ = emit_receive(
        &app,
        "reset_wallet_status",
        json!({ "code": 0, "message": "OK" }),
      );
    }
  }));
}
