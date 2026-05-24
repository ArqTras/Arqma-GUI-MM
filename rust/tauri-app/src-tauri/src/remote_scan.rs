use serde_json::json;
use std::time::Duration;

/// Pick fastest remote (like `app.scan` + POST `get_info` in `Backend.startup`).
pub async fn pick_fastest_remote(remotes: &[(String, u16)], scan: bool) -> Option<(String, u16)> {
    if !scan || remotes.is_empty() {
        return None;
    }
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_millis(800))
        .timeout(Duration::from_millis(2500))
        .build()
        .ok()?;
    let body = json!({
      "jsonrpc": "2.0",
      "id": "0",
      "method": "get_info"
    });
    let mut best: Option<(String, u16, u128)> = None;
    for (h, p) in remotes {
        let url = format!("http://{h}:{p}/json_rpc");
        let t0 = std::time::Instant::now();
        let ok = client
            .post(&url)
            .json(&body)
            .send()
            .await
            .ok()
            .and_then(|r| r.error_for_status().ok());
        if ok.is_none() {
            continue;
        }
        let ms = t0.elapsed().as_millis();
        if best.as_ref().map(|(_, _, t)| ms < *t).unwrap_or(true) {
            best = Some((h.clone(), *p, ms));
        }
    }
    best.map(|(h, p, _)| (h, p))
}
