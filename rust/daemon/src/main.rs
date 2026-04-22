//! Optional CLI utilities — extend here (logs, daemon status, etc.).

use arqma_wallet_core::default_remote_nodes;

fn main() {
    let v = default_remote_nodes();
    println!("{}", serde_json::to_string_pretty(&v).expect("json"));
}
