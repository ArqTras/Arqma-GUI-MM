//! JSON-line gateway events on stdout for the Flutter desktop shell (see `solo_pool_sink::JsonlStdoutSoloPoolSink`).
//! Usage: `arqma_flutter_solo_pool [CONFIG_DIR]` or set `ARQMA_CONFIG_DIR` (see `resolve_paths_for_flutter_solo_pool_sidecar`).

fn main () {
  let rt = tokio::runtime::Builder::new_multi_thread()
    .enable_all()
    .build()
    .expect("tokio runtime");
  if let Err(e) = rt.block_on(arqma_wallet_lib::run_flutter_solo_pool_async()) {
    eprintln!("[arqma_flutter_solo_pool] {e}");
    std::process::exit(1);
  }
}
